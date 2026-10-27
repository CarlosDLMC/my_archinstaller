//! PipeWire: the default sink and source, their volume and mute - what the
//! QML bar gets from Quickshell.Services.Pipewire. Event-driven: PipeWire's
//! loop fd sits in the bar's event loop, nothing is polled.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use pipewire as pw;
use pw::metadata::{Metadata, MetadataListener};
use pw::node::{Node, NodeListener};
use pw::spa::param::ParamType;
use pw::spa::pod::deserialize::PodDeserializer;
use pw::spa::pod::{Value, ValueArray};
use pw::types::ObjectType;

#[derive(Clone, Default, Debug)]
pub struct NodeInfo {
    pub name: String,
    pub description: String,
    pub nick: String,
}

#[derive(Clone, Default, Debug, PartialEq)]
pub struct Audio {
    pub ready: bool,
    /// Quickshell's PwNodeAudio.volume: the mean of the channel volumes,
    /// cube-rooted (the scale pavucontrol and wpctl show).
    pub volume: f32,
    pub muted: bool,
}

#[derive(Default)]
struct State {
    nodes: HashMap<u32, (NodeInfo, pw::registry::GlobalObject<pw::properties::PropertiesBox>)>,
    default_sink: String,
    default_source: String,
    metadata: Option<(Metadata, MetadataListener)>,
    sink: Option<(u32, Node, NodeListener)>,
    source: Option<(u32, Node, NodeListener)>,
    sink_audio: Audio,
    source_audio: Audio,
    changed: bool,
}

pub struct Pw {
    mainloop: pw::main_loop::MainLoopRc,
    _context: pw::context::ContextRc,
    _core: pw::core::CoreRc,
    registry: Rc<pw::registry::RegistryRc>,
    _reg_listener: pw::registry::Listener,
    state: Rc<RefCell<State>>,
}

fn default_name(value: Option<&str>) -> String {
    value
        .and_then(|v| serde_json::from_str::<serde_json::Value>(v).ok())
        .and_then(|j| j.get("name").and_then(|n| n.as_str()).map(String::from))
        .unwrap_or_default()
}

fn parse_props(pod: &pw::spa::pod::Pod, audio: &mut Audio) -> bool {
    let Ok((_, Value::Object(obj))) = PodDeserializer::deserialize_any_from(pod.as_bytes()) else { return false };
    let mut changed = false;
    for p in obj.properties {
        match p.key {
            pw::spa::sys::SPA_PROP_channelVolumes => {
                if let Value::ValueArray(ValueArray::Float(v)) = p.value {
                    if !v.is_empty() {
                        let mean = v.iter().map(|x| x.cbrt()).sum::<f32>() / v.len() as f32;
                        audio.volume = mean;
                        audio.ready = true;
                        changed = true;
                    }
                }
            }
            pw::spa::sys::SPA_PROP_mute => {
                if let Value::Bool(b) = p.value {
                    audio.muted = b;
                    changed = true;
                }
            }
            _ => {}
        }
    }
    changed
}

impl Pw {
    pub fn new() -> Option<Pw> {
        pw::init();
        let mainloop = pw::main_loop::MainLoopRc::new(None).ok()?;
        let context = pw::context::ContextRc::new(&mainloop, None).ok()?;
        let core = context.connect_rc(None).ok()?;
        let registry = Rc::new(core.get_registry_rc().ok()?);
        let state = Rc::new(RefCell::new(State::default()));
        let st = state.clone();
        let reg = Rc::downgrade(&registry);
        let st_rm = state.clone();
        let reg_listener = registry
            .add_listener_local()
            .global(move |g| {
                let props = g.props;
                match g.type_ {
                    ObjectType::Node => {
                        let get = |k: &str| props.and_then(|p| p.get(k)).unwrap_or("").to_string();
                        if !get("media.class").starts_with("Audio/") {
                            return;
                        }
                        let info = NodeInfo { name: get("node.name"), description: get("node.description"), nick: get("node.nick") };
                        let mut s = st.borrow_mut();
                        s.nodes.insert(g.id, (info, g.to_owned()));
                        s.changed = true;
                    }
                    ObjectType::Metadata => {
                        if props.and_then(|p| p.get("metadata.name")) != Some("default") {
                            return;
                        }
                        let Some(reg) = reg.upgrade() else { return };
                        let Ok(md) = reg.bind::<Metadata, _>(g) else { return };
                        let st2 = st.clone();
                        let l = md
                            .add_listener_local()
                            .property(move |_, key, _, value| {
                                let mut s = st2.borrow_mut();
                                match key {
                                    Some("default.audio.sink") => s.default_sink = default_name(value),
                                    Some("default.audio.source") => s.default_source = default_name(value),
                                    _ => return 0,
                                }
                                s.changed = true;
                                0
                            })
                            .register();
                        st.borrow_mut().metadata = Some((md, l));
                    }
                    _ => {}
                }
            })
            .global_remove(move |id| {
                let mut s = st_rm.borrow_mut();
                s.nodes.remove(&id);
                if s.sink.as_ref().map_or(false, |x| x.0 == id) {
                    s.sink = None;
                    s.sink_audio = Audio::default();
                }
                if s.source.as_ref().map_or(false, |x| x.0 == id) {
                    s.source = None;
                    s.source_audio = Audio::default();
                }
                s.changed = true;
            })
            .register();
        Some(Pw { mainloop, _context: context, _core: core, registry, _reg_listener: reg_listener, state })
    }

    pub fn fd(&self) -> std::os::fd::RawFd {
        use std::os::fd::AsRawFd;
        self.mainloop.loop_().fd().as_raw_fd()
    }

    /// Runs PipeWire's pending callbacks; true when what the bar shows changed.
    pub fn dispatch(&self) -> bool {
        self.mainloop.loop_().iterate(std::time::Duration::ZERO);
        self.follow_defaults();
        let mut s = self.state.borrow_mut();
        std::mem::take(&mut s.changed)
    }

    /// Binds the node that is the default sink/source now, if it changed.
    fn follow_defaults(&self) {
        let mut s = self.state.borrow_mut();
        for sink in [true, false] {
            let want = if sink { s.default_sink.clone() } else { s.default_source.clone() };
            let id = s.nodes.iter().find(|(_, n)| n.0.name == want).map(|(id, _)| *id);
            let bound = if sink { s.sink.as_ref().map(|x| x.0) } else { s.source.as_ref().map(|x| x.0) };
            if id == bound {
                continue;
            }
            let slot = id.and_then(|id| {
                let g = &s.nodes.get(&id)?.1;
                self.bind_node(g, sink).map(|(n, l)| (id, n, l))
            });
            if sink {
                s.sink = slot;
                s.sink_audio = Audio::default();
            } else {
                s.source = slot;
                s.source_audio = Audio::default();
            }
            s.changed = true;
        }
    }

    fn bind_node(&self, g: &pw::registry::GlobalObject<pw::properties::PropertiesBox>, sink: bool) -> Option<(Node, NodeListener)> {
        let node: Node = self.registry.bind(g).ok()?;
        let st = self.state.clone();
        let l = node
            .add_listener_local()
            .param(move |_, ty, _, _, pod| {
                if ty != ParamType::Props {
                    return;
                }
                let Some(pod) = pod else { return };
                let mut s = st.borrow_mut();
                let changed = if sink { parse_props(pod, &mut s.sink_audio) } else { parse_props(pod, &mut s.source_audio) };
                s.changed |= changed;
            })
            .register();
        node.subscribe_params(&[ParamType::Props]);
        Some((node, l))
    }

    pub fn sink(&self) -> (Audio, Option<NodeInfo>) {
        let s = self.state.borrow();
        let info = s.sink.as_ref().and_then(|x| s.nodes.get(&x.0).map(|n| n.0.clone()));
        (s.sink_audio.clone(), info)
    }

    pub fn source(&self) -> (Audio, Option<NodeInfo>) {
        let s = self.state.borrow();
        let info = s.source.as_ref().and_then(|x| s.nodes.get(&x.0).map(|n| n.0.clone()));
        (s.source_audio.clone(), info)
    }
}

//! PipeWire: the default sink and source, their volume and mute - what the
//! QML bar gets from Quickshell.Services.Pipewire. Event-driven: PipeWire's
//! loop fd sits in the bar's event loop, nothing is polled.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use pipewire as pw;
use pw::device::{Device, DeviceListener};
use pw::metadata::{Metadata, MetadataListener};
use pw::node::{Node, NodeListener};
use pw::spa::param::ParamType;
use pw::spa::pod::deserialize::PodDeserializer;
use pw::spa::pod::{Value, ValueArray};
use pw::types::ObjectType;

#[derive(Clone, Default, Debug)]
pub struct NodeInfo {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub nick: String,
    pub class: String,
    pub app_name: String,
    pub media_name: String,
    pub icon_name: String,
    pub product_name: String,
    pub profile_description: String,
    /// device.id and card.profile.device: the card and the route index a
    /// device node's volume lives on (PwNode::shouldUseDevice).
    pub device: Option<(u32, i32)>,
    pub pro_audio: bool,
}

impl NodeInfo {
    pub fn is_sink(&self) -> bool {
        self.class == "Audio/Sink"
    }
    /// A capture device (Audio/Source, Audio/Source/Virtual, Audio/Duplex).
    pub fn is_source(&self) -> bool {
        self.class.starts_with("Audio/Source") || self.class == "Audio/Duplex"
    }
    pub fn is_playback_stream(&self) -> bool {
        self.class == "Stream/Output/Audio"
    }
}

#[derive(Clone, Default, Debug, PartialEq)]
pub struct Audio {
    pub ready: bool,
    pub channels: usize,
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
    /// Nodes whose Props are followed: the defaults always, every listed
    /// device and stream while the audio card is open (PwObjectTracker).
    bound: HashMap<u32, (Node, NodeListener)>,
    audio: HashMap<u32, Audio>,
    /// The audio cards and the route device indexes each one has (PwDevice::hasRouteDevice).
    devices: HashMap<u32, (Device, DeviceListener)>,
    routes: HashMap<u32, Vec<i32>>,
    track_all: bool,
    changed: bool,
}

pub struct Pw {
    mainloop: pw::main_loop::MainLoopRc,
    _context: pw::context::ContextRc,
    core: pw::core::CoreRc,
    /// The peak monitor (PwNodePeakMonitor) while the audio card shows a source.
    peak: Option<(u32, pw::stream::StreamRc, pw::stream::StreamListener<Rc<std::cell::Cell<f32>>>)>,
    peak_value: Rc<std::cell::Cell<f32>>,
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
                        audio.channels = v.len();
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
                        let class = get("media.class");
                        if !class.starts_with("Audio/") && class != "Stream/Output/Audio" {
                            return;
                        }
                        let info = NodeInfo {
                            id: g.id,
                            name: get("node.name"),
                            description: get("node.description"),
                            nick: get("node.nick"),
                            class: get("media.class"),
                            app_name: get("application.name"),
                            media_name: get("media.name"),
                            icon_name: get("device.icon-name"),
                            product_name: get("device.product.name"),
                            profile_description: get("device.profile.description"),
                            device: get("device.id").parse().ok().zip(get("card.profile.device").parse().ok()),
                            pro_audio: matches!(get("device.profile.pro").as_str(), "true" | "1"),
                        };
                        let mut s = st.borrow_mut();
                        s.nodes.insert(g.id, (info, g.to_owned()));
                        s.changed = true;
                    }
                    ObjectType::Device => {
                        if props.and_then(|p| p.get("media.class")) != Some("Audio/Device") {
                            return;
                        }
                        let Some(reg) = reg.upgrade() else { return };
                        let Ok(dev) = reg.bind::<Device, _>(g) else { return };
                        let (st2, id) = (st.clone(), g.id);
                        let l = dev
                            .add_listener_local()
                            .param(move |_, ty, _, _, pod| {
                                if ty != ParamType::Route {
                                    return;
                                }
                                let Some(pod) = pod else { return };
                                let Ok((_, Value::Object(obj))) = PodDeserializer::deserialize_any_from(pod.as_bytes()) else { return };
                                for p in obj.properties {
                                    if let (pw::spa::sys::SPA_PARAM_ROUTE_device, Value::Int(d)) = (p.key, p.value) {
                                        let mut s = st2.borrow_mut();
                                        let r = s.routes.entry(id).or_default();
                                        if !r.contains(&d) {
                                            r.push(d);
                                        }
                                    }
                                }
                            })
                            .register();
                        dev.subscribe_params(&[ParamType::Route]);
                        st.borrow_mut().devices.insert(g.id, (dev, l));
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
                s.bound.remove(&id);
                s.audio.remove(&id);
                s.devices.remove(&id);
                s.routes.remove(&id);
                s.changed = true;
            })
            .register();
        Some(Pw { mainloop, _context: context, core, peak: None, peak_value: Rc::new(std::cell::Cell::new(0.0)), registry, _reg_listener: reg_listener, state })
    }

    pub fn fd(&self) -> std::os::fd::RawFd {
        use std::os::fd::AsRawFd;
        self.mainloop.loop_().fd().as_raw_fd()
    }

    /// Runs PipeWire's pending callbacks; true when what the bar shows changed.
    pub fn dispatch(&self) -> bool {
        self.mainloop.loop_().iterate(std::time::Duration::ZERO);
        self.follow();
        let mut s = self.state.borrow_mut();
        std::mem::take(&mut s.changed)
    }

    fn id_of(&self, name: &str) -> Option<u32> {
        self.state.borrow().nodes.iter().find(|(_, n)| n.0.name == name).map(|(id, _)| *id)
    }

    /// Keeps the bound set equal to what should be tracked.
    fn follow(&self) {
        let (want, have): (Vec<u32>, Vec<u32>) = {
            let s = self.state.borrow();
            let mut want: Vec<u32> = Vec::new();
            for name in [&s.default_sink, &s.default_source] {
                if let Some(id) = s.nodes.iter().find(|(_, n)| &n.0.name == name).map(|(id, _)| *id) {
                    want.push(id);
                }
            }
            if s.track_all {
                for (id, n) in &s.nodes {
                    if (n.0.is_sink() || n.0.is_source() || n.0.is_playback_stream()) && !want.contains(id) {
                        want.push(*id);
                    }
                }
            }
            (want, s.bound.keys().copied().collect())
        };
        for id in &have {
            if !want.contains(id) {
                let mut s = self.state.borrow_mut();
                s.bound.remove(id);
                s.audio.remove(id);
            }
        }
        for id in want {
            if have.contains(&id) {
                continue;
            }
            let bound = {
                let s = self.state.borrow();
                s.nodes.get(&id).and_then(|n| self.bind_node(&n.1, id))
            };
            if let Some(b) = bound {
                let mut s = self.state.borrow_mut();
                s.bound.insert(id, b);
                s.changed = true;
            }
        }
    }

    fn bind_node(&self, g: &pw::registry::GlobalObject<pw::properties::PropertiesBox>, id: u32) -> Option<(Node, NodeListener)> {
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
                let mut a = s.audio.get(&id).cloned().unwrap_or_default();
                if parse_props(pod, &mut a) {
                    s.audio.insert(id, a);
                    s.changed = true;
                }
            })
            .register();
        node.subscribe_params(&[ParamType::Props]);
        Some((node, l))
    }

    /// PwObjectTracker over every device and stream: on while the audio card is open.
    pub fn track_all(&self, on: bool) {
        self.state.borrow_mut().track_all = on;
        self.follow();
    }

    fn view(&self, id: u32) -> (Audio, Option<NodeInfo>) {
        let s = self.state.borrow();
        (s.audio.get(&id).cloned().unwrap_or_default(), s.nodes.get(&id).map(|n| n.0.clone()))
    }

    pub fn sink(&self) -> (Audio, Option<NodeInfo>) {
        let name = self.state.borrow().default_sink.clone();
        self.id_of(&name).map(|id| self.view(id)).unwrap_or_default()
    }

    pub fn source(&self) -> (Audio, Option<NodeInfo>) {
        let name = self.state.borrow().default_source.clone();
        self.id_of(&name).map(|id| self.view(id)).unwrap_or_default()
    }

    /// Every audio node with its tracked audio, sorted by id (registry order).
    pub fn nodes(&self) -> Vec<(NodeInfo, Audio)> {
        let s = self.state.borrow();
        let mut v: Vec<(NodeInfo, Audio)> = s.nodes.values().map(|n| (n.0.clone(), s.audio.get(&n.0.id).cloned().unwrap_or_default())).collect();
        v.sort_by_key(|n| n.0.id);
        v
    }

    fn props_pod(property: pw::spa::pod::Property) -> Vec<u8> {
        use pw::spa::pod::{serialize::PodSerializer, Object};
        let obj = Value::Object(Object { type_: pw::spa::sys::SPA_TYPE_OBJECT_Props, id: pw::spa::sys::SPA_PARAM_Props, properties: vec![property] });
        PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &obj).map(|r| r.0.into_inner()).unwrap_or_default()
    }

    /// PwNodeAudio.volume = v: every channel at v cubed (the inverse of the read).
    pub fn set_volume(&self, id: u32, v: f32) {
        let s = self.state.borrow();
        let Some((node, _)) = s.bound.get(&id) else { return };
        let n = s.audio.get(&id).map_or(2, |a| a.channels.max(1));
        let lin = v.max(0.0).powi(3);
        let bytes = Self::props_pod(pw::spa::pod::Property { key: pw::spa::sys::SPA_PROP_channelVolumes, flags: pw::spa::pod::PropertyFlags::empty(), value: Value::ValueArray(ValueArray::Float(vec![lin; n])) });
        if let Some(pod) = pw::spa::pod::Pod::from_bytes(&bytes) {
            node.set_param(ParamType::Props, 0, pod);
        }
    }

    pub fn set_mute(&self, id: u32, muted: bool) {
        let s = self.state.borrow();
        let Some((node, _)) = s.bound.get(&id) else { return };
        let bytes = Self::props_pod(pw::spa::pod::Property { key: pw::spa::sys::SPA_PROP_mute, flags: pw::spa::pod::PropertyFlags::empty(), value: Value::Bool(muted) });
        if let Some(pod) = pw::spa::pod::Pod::from_bytes(&bytes) {
            node.set_param(ParamType::Props, 0, pod);
        }
    }

    /// Pipewire.preferredDefaultAudioSink/Source = node.
    pub fn set_default(&self, sink: bool, name: &str) {
        let s = self.state.borrow();
        let Some((md, _)) = &s.metadata else { return };
        let key = if sink { "default.configured.audio.sink" } else { "default.configured.audio.source" };
        let value = serde_json::json!({ "name": name }).to_string();
        md.set_property(0, key, Some("Spa:String:JSON"), Some(&value));
    }

    /// PwNodePeakMonitor on `id` (None stops it); peak() is the last buffer's
    /// peak. A stream like quickshell's: not passive, so it wakes a suspended
    /// microphone while the audio card is open - a passive one only heard the
    /// mic while something else was recording, and the meter sat still.
    pub fn monitor_peak(&mut self, id: Option<u32>) {
        if self.peak.as_ref().map(|p| p.0) == id {
            return;
        }
        self.peak = None;
        self.peak_value.set(0.0);
        let Some(id) = id else { return };
        let target = self.state.borrow().nodes.get(&id).map(|n| n.0.name.clone()).unwrap_or_default();
        let sink = self.state.borrow().nodes.get(&id).map_or(false, |n| n.0.is_sink());
        let props = pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Audio",
            *pw::keys::MEDIA_CATEGORY => "Monitor",
            *pw::keys::MEDIA_NAME => "Peak detect",
            *pw::keys::APP_NAME => "Quickshell Peak Detect",
            "stream.monitor" => "true",
            "stream.capture.sink" => if sink { "true" } else { "false" },
            "target.object" => target.as_str(),
        };
        let Ok(stream) = pw::stream::StreamRc::new(self.core.clone(), "quickshell-peak-monitor", props) else { return };
        let Ok(listener) = stream
            .add_local_listener_with_user_data(self.peak_value.clone())
            .process(|stream, peak| {
                let Some(mut buf) = stream.dequeue_buffer() else { return };
                let datas = buf.datas_mut();
                let Some(d) = datas.first_mut() else { return };
                let (off, n) = (d.chunk().offset() as usize, d.chunk().size() as usize);
                let Some(bytes) = d.data() else { return };
                let mut p = 0f32;
                for c in bytes[off.min(bytes.len())..(off + n).min(bytes.len())].chunks_exact(4) {
                    p = p.max(f32::from_le_bytes([c[0], c[1], c[2], c[3]]).abs());
                }
                peak.set(p);
            })
            .register()
        else {
            return;
        };
        let mut info = pw::spa::param::audio::AudioInfoRaw::new();
        info.set_format(pw::spa::param::audio::AudioFormat::F32LE);
        let obj = Value::Object(pw::spa::pod::Object { type_: pw::spa::sys::SPA_TYPE_OBJECT_Format, id: pw::spa::sys::SPA_PARAM_EnumFormat, properties: info.into() });
        let Ok(bytes) = pw::spa::pod::serialize::PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &obj).map(|r| r.0.into_inner()) else { return };
        let Some(pod) = pw::spa::pod::Pod::from_bytes(&bytes) else { return };
        let mut params = [pod];
        if stream.connect(pw::spa::utils::Direction::Input, None, pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS, &mut params).is_ok() {
            self.peak = Some((id, stream, listener));
        }
    }

    /// PwNodePeakMonitor.peak: the cube root of the sample peak (the scale
    /// the volumes are on), undone by the node's own volume unless that volume
    /// is the card's route (PwNode::shouldUseDevice), as quickshell does.
    pub fn peak(&self) -> f32 {
        let Some((id, ..)) = &self.peak else { return 0.0 };
        let mut v = self.peak_value.get().cbrt();
        let s = self.state.borrow();
        let on_device = s.nodes.get(id).map_or(false, |n| {
            !n.0.pro_audio && n.0.device.map_or(false, |(dev, route)| s.routes.get(&dev).map_or(false, |r| r.contains(&route)))
        });
        if !on_device {
            if let Some(a) = s.audio.get(id).filter(|a| a.ready && a.volume != 0.0) {
                v /= a.volume;
            }
        }
        v
    }
}

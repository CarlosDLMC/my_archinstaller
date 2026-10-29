//! PipeWire: the default sink and source, their volume and mute, and the
//! nodes the audio card lists - what the QML bar gets from
//! Quickshell.Services.Pipewire. Event-driven: PipeWire's loop fd sits in the
//! bar's event loop, nothing is polled.

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::time::{Duration, Instant};

use pipewire as pw;
use pw::device::{Device, DeviceListener};
use pw::metadata::{Metadata, MetadataListener};
use pw::node::{Node, NodeChangeMask, NodeListener};
use pw::spa::param::{ParamInfoFlags, ParamType};
use pw::spa::pod::deserialize::PodDeserializer;
use pw::spa::pod::{Object, Pod, Property, PropertyFlags, Value, ValueArray};
use pw::types::ObjectType;

/// What quickshell makes of a node's media.class (PwNodeType): exact classes
/// only. Anything else (Audio/Source/Virtual, ...) has no `audio` and is in
/// none of the card's lists.
#[derive(Clone, Copy, Default, Debug, PartialEq, Eq)]
enum Kind {
    #[default]
    Untracked,
    AudioSink,
    AudioSource,
    AudioDuplex,
    AudioOutStream,
    VideoSink,
}

impl Kind {
    fn of(class: &str) -> Kind {
        match class {
            "Audio/Sink" => Kind::AudioSink,
            "Audio/Source" => Kind::AudioSource,
            "Audio/Duplex" => Kind::AudioDuplex,
            "Stream/Output/Audio" => Kind::AudioOutStream,
            "Video/Sink" => Kind::VideoSink,
            _ => Kind::Untracked,
        }
    }

    /// PwNodeType::Audio: the node has a PwNodeAudio (volume and mute).
    fn audio(self) -> bool {
        matches!(self, Kind::AudioSink | Kind::AudioSource | Kind::AudioDuplex | Kind::AudioOutStream)
    }

    /// PwNodeType::Sink (isSink).
    fn sink(self) -> bool {
        matches!(self, Kind::AudioSink | Kind::AudioDuplex | Kind::AudioOutStream | Kind::VideoSink)
    }
}

#[derive(Clone, Default, Debug, PartialEq)]
pub struct NodeInfo {
    pub id: u32,
    pub name: String,
    pub description: String,
    pub nick: String,
    pub app_name: String,
    /// From the node's info once it is bound - the registry carries 17 keys,
    /// none of these: what nodeLabel, nodeBlob and streamLabel read from
    /// node.properties.
    pub media_name: String,
    pub icon_name: String,
    pub product_name: String,
    pub profile_description: String,
    kind: Kind,
    /// Arrival order: Pipewire.nodes keeps it (PipeWire reuses ids).
    seq: u64,
    /// device.id; card.profile.device and device.profile.pro from the info
    /// (PwNode::shouldUseDevice).
    device: Option<u32>,
    route: Option<i32>,
    pro_audio: bool,
}

impl NodeInfo {
    /// sinkList: isSink && !isStream (Audio/Sink, Audio/Duplex, Video/Sink).
    pub fn is_sink(&self) -> bool {
        self.kind.sink() && self.kind != Kind::AudioOutStream
    }

    /// sourceList: an audio node neither sink nor stream (Audio/Source), less
    /// the bar's own client and the mic noise filter (VolumeWidget.qml:153-172).
    pub fn is_source(&self) -> bool {
        self.kind == Kind::AudioSource && self.name != "quickshell" && self.name != "mic_denoise"
    }

    /// streamList: Stream/Output/Audio.
    pub fn is_playback_stream(&self) -> bool {
        self.kind == Kind::AudioOutStream
    }

    /// PwNode::unbindHooks: the info's properties go with the binding.
    fn clear_info(&mut self) {
        (self.media_name, self.icon_name, self.product_name, self.profile_description) = Default::default();
        (self.route, self.pro_audio) = (None, false);
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

/// PwVolumeProps: what a Props object says about volume.
#[derive(Clone, Default, PartialEq)]
struct VolumeProps {
    /// Cube-rooted channel volumes.
    volumes: Vec<f32>,
    channels: Vec<u32>,
    mute: bool,
    /// SPA_PROP_volumeStep (-1 in quickshell when there is none).
    step: Option<f32>,
}

impl VolumeProps {
    /// PwVolumeProps::parseSpaPod.
    fn parse(props: &[Property]) -> VolumeProps {
        let mut p = VolumeProps::default();
        for prop in props {
            match (prop.key, &prop.value) {
                (pw::spa::sys::SPA_PROP_channelVolumes, Value::ValueArray(ValueArray::Float(v))) => p.volumes = v.iter().map(|x| x.cbrt()).collect(),
                (pw::spa::sys::SPA_PROP_channelMap, Value::ValueArray(ValueArray::Id(v))) => p.channels = v.iter().map(|c| c.0).collect(),
                (pw::spa::sys::SPA_PROP_mute, Value::Bool(b)) => p.mute = *b,
                (pw::spa::sys::SPA_PROP_volumeStep, Value::Float(f)) => p.step = Some(*f),
                _ => {}
            }
        }
        if p.channels.is_empty() {
            // No channel map: the usual layout for the count (spa/param/audio/layout.h).
            use pw::spa::sys::*;
            p.channels = match p.volumes.len() {
                1 => vec![SPA_AUDIO_CHANNEL_MONO],
                2 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR],
                3 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_LFE],
                4 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR],
                5 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR],
                6 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR],
                7 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR],
                8 => vec![SPA_AUDIO_CHANNEL_FL, SPA_AUDIO_CHANNEL_FR, SPA_AUDIO_CHANNEL_FC, SPA_AUDIO_CHANNEL_LFE, SPA_AUDIO_CHANNEL_RL, SPA_AUDIO_CHANNEL_RR, SPA_AUDIO_CHANNEL_SL, SPA_AUDIO_CHANNEL_SR],
                _ => Vec::new(),
            };
        }
        p
    }
}

/// PwNodeBoundAudio: a bound audio node's volume.
#[derive(Default)]
struct Vol {
    channels: Vec<u32>,
    /// mVolumes: cube-rooted, set as soon as a write goes out.
    volumes: Vec<f32>,
    /// mServerVolumes: what the server last said.
    server: Vec<f32>,
    /// The device path: the last route write, and the one held back while
    /// the card has not answered the previous (mDeviceVolumes, waitingVolumes).
    device: Vec<f32>,
    waiting: Vec<f32>,
    muted: bool,
    step: Option<f32>,
}

impl Vol {
    /// PwNodeAudio as QML reads it: averageVolume() and muted.
    fn audio(&self) -> Audio {
        let n = self.volumes.len();
        let volume = if n == 0 { 0.0 } else { self.volumes.iter().sum::<f32>() / n as f32 };
        Audio { ready: n > 0, channels: n, volume, muted: self.muted }
    }
}

/// PwNodeBoundAudio::updateVolumeProps; true when what shows changed.
fn update_volume_props(v: &mut Vol, p: &VolumeProps) -> bool {
    if p.volumes.len() != p.channels.len() {
        return false;
    }
    let changed = v.volumes != p.volumes || v.muted != p.mute;
    v.step = p.step;
    v.channels = p.channels.clone();
    v.server = p.volumes.clone();
    v.volumes = p.volumes.clone();
    v.muted = p.mute;
    changed
}

/// PwDevice: an audio card, its active routes and their volumes.
struct Dev {
    /// First: it unhooks while the proxy still lives.
    _listener: DeviceListener,
    proxy: Device,
    /// routeDeviceIndexes: route device -> route index.
    routes: HashMap<i32, i32>,
    /// stagingIndexes: the route devices the enumeration in progress listed.
    staging: Vec<i32>,
    /// routeDeviceVolumes.
    volumes: HashMap<i32, VolumeProps>,
    /// deviceResponded, mWaitingForDevice.
    responded: bool,
    waiting: bool,
}

#[derive(Default)]
struct State {
    nodes: HashMap<u32, (NodeInfo, pw::registry::GlobalObject<pw::properties::PropertiesBox>)>,
    seq: u64,
    default_sink: String,
    default_source: String,
    /// The "default" metadata: its global id, the listener, the proxy.
    metadata: Option<(u32, MetadataListener, Metadata)>,
    /// Bound nodes, listener before proxy: the defaults and every node the
    /// card lists, all the time (VolumeWidget's PwObjectTrackers).
    bound: HashMap<u32, (NodeListener, Node)>,
    vols: HashMap<u32, Vol>,
    devices: HashMap<u32, Dev>,
    /// The audio card is open: its lists show and its meter runs.
    track_all: bool,
    /// Nodes or defaults came or went.
    topo: bool,
    changed: bool,
    /// The daemon went away (PwCore::onError).
    fatal: bool,
}

/// PwNode::shouldUseDevice: the node's volume lives on its card's route.
fn on_device(s: &State, n: &NodeInfo) -> Option<(u32, i32)> {
    let (dev, route) = (n.device?, n.route?);
    (!n.pro_audio && s.devices.get(&dev)?.routes.contains_key(&route)).then_some((dev, route))
}

fn object(pod: &Pod) -> Option<Object> {
    match PodDeserializer::deserialize_any_from(pod.as_bytes()) {
        Ok((_, Value::Object(obj))) => Some(obj),
        _ => None,
    }
}

fn prop(key: u32, value: Value) -> Property {
    Property { key, flags: PropertyFlags::empty(), value }
}

fn props_object(properties: Vec<Property>) -> Value {
    Value::Object(Object { type_: pw::spa::sys::SPA_TYPE_OBJECT_Props, id: pw::spa::sys::SPA_PARAM_Props, properties })
}

/// Props { channelVolumes } from cube-rooted volumes.
fn volumes_props(volumes: &[f32]) -> Value {
    props_object(vec![prop(pw::spa::sys::SPA_PROP_channelVolumes, Value::ValueArray(ValueArray::Float(volumes.iter().map(|v| v * v * v).collect())))])
}

fn mute_props(muted: bool) -> Value {
    props_object(vec![prop(pw::spa::sys::SPA_PROP_mute, Value::Bool(muted))])
}

/// Serializes a pod and hands it to `send`.
fn with_pod(value: &Value, send: impl FnOnce(&Pod)) {
    use pw::spa::pod::serialize::PodSerializer;
    if let Ok((cursor, _)) = PodSerializer::serialize(std::io::Cursor::new(Vec::new()), value) {
        if let Some(pod) = Pod::from_bytes(&cursor.into_inner()) {
            send(pod);
        }
    }
}

/// PwDevice::setRouteProps: `props` on the route that route device is on,
/// saved (WirePlumber keeps it across logins, pamixer and pavucontrol read it).
fn write_route(d: &Dev, route: i32, props: Value) -> bool {
    let Some(&index) = d.routes.get(&route) else { return false };
    let value = Value::Object(Object {
        type_: pw::spa::sys::SPA_TYPE_OBJECT_ParamRoute,
        id: pw::spa::sys::SPA_PARAM_Route,
        properties: vec![
            prop(pw::spa::sys::SPA_PARAM_ROUTE_device, Value::Int(route)),
            prop(pw::spa::sys::SPA_PARAM_ROUTE_index, Value::Int(index)),
            prop(pw::spa::sys::SPA_PARAM_ROUTE_props, props),
            prop(pw::spa::sys::SPA_PARAM_ROUTE_save, Value::Bool(true)),
        ],
    });
    with_pod(&value, |pod| d.proxy.set_param(ParamType::Route, 0, pod));
    true
}

/// PwDevice::onInfo: changed params mean its routes are read again.
fn device_info(st: &RefCell<State>, dev: u32, info: &pw::device::DeviceInfoRef) {
    if info.as_raw().change_mask & pw::sys::PW_DEVICE_CHANGE_MASK_PARAMS as u64 == 0 {
        return;
    }
    let Some(p) = info.params().iter().find(|p| p.id() == ParamType::Route) else { return };
    if !p.flags().contains(ParamInfoFlags::READWRITE) {
        return;
    }
    let mut s = st.borrow_mut();
    let Some(d) = s.devices.get_mut(&dev) else { return };
    d.staging.clear();
    d.responded = false;
    d.proxy.enum_params(0, Some(ParamType::Route), 0, u32::MAX);
}

/// PwDevice::onParam: a route of the card. The first answer since the
/// last write lets held-back volumes go (deviceReady); each route's volume
/// reaches the nodes on it (routeVolumesChanged).
fn device_route(st: &RefCell<State>, dev: u32, pod: Option<&Pod>) {
    let mut guard = st.borrow_mut();
    let s = &mut *guard;
    let Some(d) = s.devices.get_mut(&dev) else { return };
    let ready = !d.responded && {
        d.responded = true;
        std::mem::take(&mut d.waiting)
    };
    if ready {
        device_ready(s, dev);
    }
    let Some(obj) = pod.and_then(object) else { return };
    let (mut route, mut index, mut props) = (None, None, None);
    for p in obj.properties {
        match (p.key, p.value) {
            (pw::spa::sys::SPA_PARAM_ROUTE_device, Value::Int(v)) => route = Some(v),
            (pw::spa::sys::SPA_PARAM_ROUTE_index, Value::Int(v)) => index = Some(v),
            (pw::spa::sys::SPA_PARAM_ROUTE_props, Value::Object(o)) => props = Some(VolumeProps::parse(&o.properties)),
            _ => {}
        }
    }
    let (Some(route), Some(index), Some(props)) = (route, index, props) else { return };
    let Some(d) = s.devices.get_mut(&dev) else { return };
    d.staging.push(route);
    d.routes.insert(route, index);
    d.volumes.insert(route, props.clone());
    let on: Vec<u32> = s.nodes.values().map(|n| &n.0).filter(|n| n.kind.audio() && s.bound.contains_key(&n.id) && on_device(s, n) == Some((dev, route))).map(|n| n.id).collect();
    for id in on {
        if update_volume_props(s.vols.entry(id).or_default(), &props) {
            s.changed = true;
        }
    }
}

/// PwNodeBoundAudio::onDeviceReady: the last volume held back while the
/// card had not answered goes out now.
fn device_ready(s: &mut State, dev: u32) {
    let on: Vec<(u32, i32)> = s.nodes.values().map(|n| &n.0).filter(|n| n.device == Some(dev) && n.kind.audio() && s.bound.contains_key(&n.id)).map(|n| (n.id, n.route.unwrap_or(-1))).collect();
    for (id, route) in on {
        let Some(v) = s.vols.get_mut(&id) else { continue };
        let waiting = std::mem::take(&mut v.waiting);
        if waiting.is_empty() || waiting == v.device {
            continue;
        }
        if let Some(d) = s.devices.get(&dev) {
            write_route(d, route, volumes_props(&waiting));
        }
        v.device = waiting.clone();
        v.volumes = waiting;
        s.changed = true;
    }
}

/// PwNodePeakMonitor's stream. The listener first: it unhooks while the
/// stream still lives (the other order wrote into the freed stream).
struct Peak {
    node: u32,
    _listener: pw::stream::StreamListener<Rc<Cell<f32>>>,
    _stream: pw::stream::StreamRc,
}

/// What one connection to the daemon made, dropped in field order: each
/// listener before its object, every proxy before the core (the State's
/// proxies are cleared before this goes).
struct Conn {
    peak: Option<Peak>,
    _reg_listener: pw::registry::Listener,
    registry: Rc<pw::registry::RegistryRc>,
    _core_listener: pw::core::Listener,
    core: pw::core::CoreRc,
}

pub struct Pw {
    conn: RefCell<Option<Conn>>,
    state: Rc<RefCell<State>>,
    peak_value: Rc<Cell<f32>>,
    /// The sink as sink() last gave it to the strip, and whether it has
    /// moved since: dispatch() says so until the strip has it.
    strip: RefCell<(Audio, Option<NodeInfo>)>,
    strip_moved: Cell<bool>,
    /// PwConnection's reconnect: tried again until the daemon answers.
    retry: pw::loop_::TimerSource<'static>,
    retry_due: Rc<Cell<bool>>,
    connected_at: Cell<Instant>,
    context: pw::context::ContextRc,
    mainloop: pw::main_loop::MainLoopRc,
}

fn default_name(value: Option<&str>) -> String {
    value
        .and_then(|v| serde_json::from_str::<serde_json::Value>(v).ok())
        .and_then(|j| j.get("name").and_then(|n| n.as_str()).map(String::from))
        .unwrap_or_default()
}

impl Pw {
    pub fn new() -> Option<Pw> {
        pw::init();
        let mainloop = pw::main_loop::MainLoopRc::new(None).ok()?;
        let context = pw::context::ContextRc::new(&mainloop, None).ok()?;
        // A loop's sources borrow it; the bar's one PipeWire loop lives as
        // long as the process, so a leaked handle lends the timer a 'static one.
        let lp: &'static pw::main_loop::MainLoopRc = Box::leak(Box::new(mainloop.clone()));
        let retry_due = Rc::new(Cell::new(false));
        let due = retry_due.clone();
        let retry = lp.loop_().add_timer(move |_| due.set(true));
        let pw = Pw {
            conn: RefCell::new(None),
            state: Rc::new(RefCell::new(State::default())),
            peak_value: Rc::new(Cell::new(0.0)),
            strip: RefCell::new(Default::default()),
            strip_moved: Cell::new(false),
            retry,
            retry_due,
            connected_at: Cell::new(Instant::now()),
            context,
            mainloop,
        };
        // Like quickshell, a daemon that is not there at start is not waited for.
        pw.connect().then_some(pw)
    }

    /// PwCore::start: the core, its error event, the registry.
    fn connect(&self) -> bool {
        let Ok(core) = self.context.connect_rc(None) else { return false };
        let Ok(registry) = core.get_registry_rc() else { return false };
        let registry = Rc::new(registry);
        let st_err = self.state.clone();
        let core_listener = core
            .add_listener_local()
            .error(move |id, _, res, _| {
                // PwCore::onError: fatal, but for the harmless ENOENTs seen
                // on device removal. The connection's own errors (a daemon
                // restart) come on the core.
                if id == pw::core::PW_ID_CORE && res != -libc::ENOENT {
                    st_err.borrow_mut().fatal = true;
                }
            })
            .register();
        let st = self.state.clone();
        let reg = Rc::downgrade(&registry);
        let st_rm = self.state.clone();
        let reg_listener = registry
            .add_listener_local()
            .global(move |g| {
                let props = g.props;
                match g.type_ {
                    ObjectType::Node => {
                        let get = |k: &str| props.and_then(|p| p.get(k)).unwrap_or("").to_string();
                        let class = get("media.class");
                        if !class.starts_with("Audio/") && class != "Stream/Output/Audio" && class != "Video/Sink" {
                            return;
                        }
                        let mut s = st.borrow_mut();
                        s.seq += 1;
                        let info = NodeInfo {
                            id: g.id,
                            name: get("node.name"),
                            description: get("node.description"),
                            nick: get("node.nick"),
                            app_name: get("application.name"),
                            kind: Kind::of(&class),
                            seq: s.seq,
                            device: get("device.id").parse().ok(),
                            ..Default::default()
                        };
                        s.nodes.insert(g.id, (info, g.to_owned()));
                        s.topo = true;
                        s.changed = true;
                    }
                    ObjectType::Device => {
                        if props.and_then(|p| p.get("media.class")) != Some("Audio/Device") {
                            return;
                        }
                        let Some(reg) = reg.upgrade() else { return };
                        let Ok(dev) = reg.bind::<Device, _>(g) else { return };
                        let (st_info, st_param, id) = (st.clone(), st.clone(), g.id);
                        let l = dev
                            .add_listener_local()
                            .info(move |info| device_info(&st_info, id, info))
                            .param(move |_, ty, _, _, pod| {
                                if ty == ParamType::Route {
                                    device_route(&st_param, id, pod);
                                }
                            })
                            .register();
                        let d = Dev { _listener: l, proxy: dev, routes: HashMap::new(), staging: Vec::new(), volumes: HashMap::new(), responded: false, waiting: false };
                        st.borrow_mut().devices.insert(g.id, d);
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
                                let name = default_name(value);
                                let slot = match key {
                                    Some("default.audio.sink") => &mut s.default_sink,
                                    Some("default.audio.source") => &mut s.default_source,
                                    _ => return 0,
                                };
                                if *slot != name {
                                    *slot = name;
                                    s.topo = true;
                                    s.changed = true;
                                }
                                0
                            })
                            .register();
                        st.borrow_mut().metadata = Some((g.id, l, md));
                    }
                    _ => {}
                }
            })
            .global_remove(move |id| {
                let mut s = st_rm.borrow_mut();
                let node = s.nodes.remove(&id).is_some();
                s.bound.remove(&id);
                s.vols.remove(&id);
                let dev = s.devices.remove(&id).is_some();
                if s.metadata.as_ref().map_or(false, |m| m.0 == id) {
                    s.metadata = None;
                }
                if node || dev {
                    s.topo |= node;
                    s.changed = true;
                }
            })
            .register();
        *self.conn.borrow_mut() = Some(Conn { peak: None, _reg_listener: reg_listener, registry, _core_listener: core_listener, core });
        self.connected_at.set(Instant::now());
        true
    }

    /// PwConnection::onFatalError: all the connection made goes, the
    /// defaults and the lists with it.
    fn teardown(&self) {
        {
            let mut s = self.state.borrow_mut();
            // The proxies before the registry and the core.
            s.bound.clear();
            s.devices.clear();
            s.metadata = None;
            s.nodes.clear();
            s.vols.clear();
            s.default_sink.clear();
            s.default_source.clear();
            s.fatal = false;
            s.changed = true;
        }
        self.peak_value.set(0.0);
        let conn = self.conn.borrow_mut().take();
        drop(conn);
    }

    pub fn fd(&self) -> std::os::fd::RawFd {
        use std::os::fd::AsRawFd;
        self.mainloop.loop_().fd().as_raw_fd()
    }

    /// Runs PipeWire's pending callbacks; true when what the bar shows
    /// changed: the strip's sink, or anything while the audio card is open.
    pub fn dispatch(&self) -> bool {
        self.mainloop.loop_().iterate(Duration::ZERO);
        let fatal = std::mem::take(&mut self.state.borrow_mut().fatal);
        if fatal {
            self.teardown();
            // PwConnection::beginReconnect: at once (a restarted daemon's
            // socket is there) - unless this connection died young.
            let young = self.connected_at.get().elapsed() < Duration::from_secs(1);
            if young || !self.connect() {
                self.retry.update_timer(Some(Duration::from_secs(1)), None);
            }
        }
        if self.retry_due.take() && self.conn.borrow().is_none() && !self.connect() {
            self.retry.update_timer(Some(Duration::from_secs(1)), None);
        }
        let topo = {
            let mut guard = self.state.borrow_mut();
            // PwDevice::polled: routes the last enumeration did not list are gone.
            for d in guard.devices.values_mut() {
                let Dev { routes, staging, .. } = d;
                if !staging.is_empty() {
                    routes.retain(|r, _| staging.contains(r));
                }
            }
            std::mem::take(&mut guard.topo)
        };
        if topo {
            self.follow();
        }
        let (any, card) = {
            let mut s = self.state.borrow_mut();
            (std::mem::take(&mut s.changed), s.track_all)
        };
        if topo || any {
            self.follow_peak();
        }
        if any && self.default_node(true) != *self.strip.borrow() {
            self.strip_moved.set(true);
        }
        self.strip_moved.get() || (any && card)
    }

    /// Keeps the bound set what VolumeWidget tracks: the defaults and every
    /// sink, source and playback stream it lists, open card or not.
    fn follow(&self) {
        let (want, have): (Vec<u32>, Vec<u32>) = {
            let s = self.state.borrow();
            let default = |n: &NodeInfo| !n.name.is_empty() && (n.name == s.default_sink || n.name == s.default_source);
            let want = s.nodes.values().map(|n| &n.0).filter(|n| n.is_sink() || n.is_source() || n.is_playback_stream() || default(n)).map(|n| n.id).collect();
            (want, s.bound.keys().copied().collect())
        };
        for id in have.iter().filter(|id| !want.contains(id)) {
            let mut s = self.state.borrow_mut();
            s.bound.remove(id);
            s.vols.remove(id);
            if let Some(n) = s.nodes.get_mut(id) {
                n.0.clear_info();
            }
            s.changed = true;
        }
        let conn = self.conn.borrow();
        let Some(c) = conn.as_ref() else { return };
        for id in want.into_iter().filter(|id| !have.contains(id)) {
            let bound = {
                let s = self.state.borrow();
                s.nodes.get(&id).and_then(|n| self.bind_node(&c.registry, &n.1, id))
            };
            if let Some(b) = bound {
                self.state.borrow_mut().bound.insert(id, b);
            }
        }
    }

    fn bind_node(&self, registry: &pw::registry::RegistryRc, g: &pw::registry::GlobalObject<pw::properties::PropertiesBox>, id: u32) -> Option<(NodeListener, Node)> {
        let node: Node = registry.bind(g).ok()?;
        let (st_info, st_param) = (self.state.clone(), self.state.clone());
        let l = node
            .add_listener_local()
            .info(move |info| {
                // PwNode::onInfo: the node's full properties.
                if !info.change_mask().contains(NodeChangeMask::PROPS) {
                    return;
                }
                let Some(props) = info.props() else { return };
                let get = |k: &str| props.get(k).unwrap_or("").to_string();
                let mut guard = st_info.borrow_mut();
                let s = &mut *guard;
                let Some((n, _)) = s.nodes.get_mut(&id) else { return };
                let before = n.clone();
                n.media_name = get("media.name");
                n.icon_name = get("device.icon-name");
                n.product_name = get("device.product.name");
                n.profile_description = get("device.profile.description");
                n.pro_audio = matches!(props.get("device.profile.pro"), Some("true" | "1"));
                let route = props.get("card.profile.device").filter(|_| n.device.is_some());
                if let Some(r) = route {
                    n.route = Some(r.parse().unwrap_or(0));
                }
                let mut changed = *n != before;
                let n = n.clone();
                if let (Some(r), true) = (n.route.filter(|_| route.is_some()), n.kind.audio()) {
                    // onDeviceChanged: the route's volume, if the card already told it.
                    if let Some(p) = n.device.and_then(|d| s.devices.get(&d)).and_then(|d| d.volumes.get(&r)).cloned() {
                        changed |= update_volume_props(s.vols.entry(id).or_default(), &p);
                    }
                }
                if changed {
                    s.changed = true;
                }
            })
            .param(move |_, ty, index, _, pod| {
                // PwNodeBoundAudio::onSpaParam: Props, unless the card's route
                // has this node's volume.
                if ty != ParamType::Props || index != 0 {
                    return;
                }
                let Some(obj) = pod.and_then(object) else { return };
                let mut guard = st_param.borrow_mut();
                let s = &mut *guard;
                let Some((n, _)) = s.nodes.get(&id) else { return };
                if !n.kind.audio() || on_device(s, n).is_some() {
                    return;
                }
                if update_volume_props(s.vols.entry(id).or_default(), &VolumeProps::parse(&obj.properties)) {
                    s.changed = true;
                }
            })
            .register();
        node.subscribe_params(&[ParamType::Props]);
        Some((l, node))
    }

    /// The audio card opened or closed: its lists show, its meter runs.
    pub fn track_all(&self, on: bool) {
        self.state.borrow_mut().track_all = on;
        self.follow_peak();
    }

    fn view(&self, id: u32) -> (Audio, Option<NodeInfo>) {
        let s = self.state.borrow();
        (s.vols.get(&id).map(Vol::audio).unwrap_or_default(), s.nodes.get(&id).map(|n| n.0.clone()))
    }

    fn default_id(&self, sink: bool) -> Option<u32> {
        let s = self.state.borrow();
        let name = if sink { &s.default_sink } else { &s.default_source };
        s.nodes.values().find(|n| !name.is_empty() && n.0.name == *name).map(|n| n.0.id)
    }

    /// Pipewire.defaultAudioSink / defaultAudioSource as they are now.
    pub fn default_node(&self, sink: bool) -> (Audio, Option<NodeInfo>) {
        self.default_id(sink).map(|id| self.view(id)).unwrap_or_default()
    }

    /// The default sink for the strip: what this returns is what the strip
    /// shows, and dispatch() compares against it.
    pub fn sink(&self) -> (Audio, Option<NodeInfo>) {
        let v = self.default_node(true);
        *self.strip.borrow_mut() = v.clone();
        self.strip_moved.set(false);
        v
    }

    pub fn source(&self) -> (Audio, Option<NodeInfo>) {
        self.default_node(false)
    }

    /// The default source's volume and mute alone (the meter's tick).
    pub fn source_audio(&self) -> Audio {
        let id = self.default_id(false);
        let s = self.state.borrow();
        id.and_then(|id| s.vols.get(&id)).map(Vol::audio).unwrap_or_default()
    }

    /// The default sink's or source's id and volume, nothing copied.
    pub fn default_audio(&self, sink: bool) -> Option<(u32, Audio)> {
        let id = self.default_id(sink)?;
        let s = self.state.borrow();
        Some((id, s.vols.get(&id).map(Vol::audio).unwrap_or_default()))
    }

    /// A playback stream the audio card lists (its volume is known) whose
    /// id `matches`, nothing copied.
    pub fn stream_audio(&self, matches: impl Fn(u32) -> bool) -> Option<(u32, Audio)> {
        let s = self.state.borrow();
        s.nodes.values().map(|n| &n.0).filter(|n| n.is_playback_stream() && matches(n.id)).find_map(|n| s.vols.get(&n.id).map(Vol::audio).filter(|a| a.ready).map(|a| (n.id, a)))
    }

    /// Every audio node with its volume, in the order they appeared (the
    /// order of Pipewire.nodes).
    pub fn nodes(&self) -> Vec<(NodeInfo, Audio)> {
        let s = self.state.borrow();
        let mut v: Vec<(NodeInfo, Audio)> = s.nodes.values().map(|n| (n.0.clone(), s.vols.get(&n.0.id).map(Vol::audio).unwrap_or_default())).collect();
        v.sort_by_key(|n| n.0.seq);
        v
    }

    /// PwNodeAudio.volume = v (setAverageVolume): each channel scaled by v
    /// over the old average, so a balance stays; every one at v from silence.
    pub fn set_volume(&self, id: u32, v: f32) {
        let volumes: Vec<f32> = {
            let s = self.state.borrow();
            let Some(vol) = s.vols.get(&id) else { return };
            let avg = vol.audio().volume;
            let mul = if avg == 0.0 { 0.0 } else { v / avg };
            vol.volumes.iter().map(|old| if mul == 0.0 { v } else { old * mul }).collect()
        };
        self.set_volumes(id, volumes);
    }

    /// PwNodeBoundAudio::setVolumes: a device node through its card's route,
    /// one write in flight at a time; anything else through its Props. Shown
    /// at once; an unchanged value is not sent.
    fn set_volumes(&self, id: u32, volumes: Vec<f32>) {
        let mut guard = self.state.borrow_mut();
        let s = &mut *guard;
        let real: Vec<f32> = volumes.iter().map(|v| v.max(0.0)).collect();
        let route = s.nodes.get(&id).and_then(|n| on_device(s, &n.0));
        let Some(vol) = s.vols.get_mut(&id) else { return };
        if real == vol.volumes || real.len() != vol.volumes.len() {
            return;
        }
        if let Some((dev, route)) = route {
            let Some(d) = s.devices.get_mut(&dev) else { return };
            if d.waiting {
                vol.waiting = real.clone();
            } else {
                // A change under the card's step brings no answer to wait for.
                let significant = vol.server.is_empty()
                    || vol.step.map_or(true, |step| vol.server.iter().enumerate().any(|(i, sv)| {
                        let t = real.get(i).copied().unwrap_or(0.0);
                        t == 0.0 || (t - sv).abs() >= step
                    }));
                if significant {
                    if !write_route(d, route, volumes_props(&real)) {
                        return;
                    }
                    vol.device = real.clone();
                    d.waiting = true;
                }
            }
        } else {
            let Some((_, node)) = s.bound.get(&id) else { return };
            with_pod(&volumes_props(&real), |pod| node.set_param(ParamType::Props, 0, pod));
        }
        vol.volumes = real;
        s.changed = true;
    }

    /// PwNodeAudio.muted = m: a device node's on its card's route.
    pub fn set_mute(&self, id: u32, muted: bool) {
        let mut guard = self.state.borrow_mut();
        let s = &mut *guard;
        let Some((n, _)) = s.nodes.get(&id) else { return };
        if !n.kind.audio() || s.vols.get(&id).map_or(false, |v| v.muted) == muted {
            return;
        }
        if let Some((dev, route)) = on_device(s, n) {
            if !s.devices.get(&dev).map_or(false, |d| write_route(d, route, mute_props(muted))) {
                return;
            }
        } else {
            let Some((_, node)) = s.bound.get(&id) else { return };
            with_pod(&mute_props(muted), |pod| node.set_param(ParamType::Props, 0, pod));
        }
        s.vols.entry(id).or_default().muted = muted;
        s.changed = true;
    }

    /// Pipewire.preferredDefaultAudioSink/Source = node.
    pub fn set_default(&self, sink: bool, name: &str) {
        let s = self.state.borrow();
        let Some((_, _, md)) = &s.metadata else { return };
        let key = if sink { "default.configured.audio.sink" } else { "default.configured.audio.source" };
        let value = serde_json::json!({ "name": name }).to_string();
        md.set_property(0, key, Some("Spa:String:JSON"), Some(&value));
    }

    /// The audio card's meter: it asks for the default source when it opens
    /// and for None when it closes; follow_peak moves it after that.
    pub fn monitor_peak(&mut self, id: Option<u32>) {
        if id.is_some() {
            self.follow_peak();
        } else {
            self.set_peak(None);
        }
    }

    /// LevelMeter { node: sourceReady ? source : null; enabled: !!node &&
    /// !muted }: while the audio card is open the meter hears the default
    /// source - the new one when it changes - and nothing while it is muted.
    fn follow_peak(&self) {
        let want = {
            let s = self.state.borrow();
            let source = s.nodes.values().map(|n| &n.0).find(|n| s.track_all && !s.default_source.is_empty() && n.name == s.default_source);
            source.filter(|n| n.kind.audio() && !s.vols.get(&n.id).map_or(false, |v| v.muted)).map(|n| n.id)
        };
        self.set_peak(want);
    }

    /// PwNodePeakMonitor on `want` (None stops it); peak() is the last
    /// buffer's peak. A stream like quickshell's: not passive, so it wakes a
    /// suspended microphone while the audio card is open - a passive one only
    /// heard the mic while something else was recording, and the meter sat still.
    fn set_peak(&self, want: Option<u32>) {
        let mut conn = self.conn.borrow_mut();
        let Some(c) = conn.as_mut() else { return };
        if c.peak.as_ref().map(|p| p.node) == want {
            return;
        }
        c.peak = None;
        self.peak_value.set(0.0);
        let Some(id) = want else { return };
        let Some((target, sink)) = self.state.borrow().nodes.get(&id).map(|n| (n.0.name.clone(), n.0.kind.sink())) else { return };
        let props = pw::properties::properties! {
            *pw::keys::MEDIA_TYPE => "Audio",
            *pw::keys::MEDIA_CATEGORY => "Monitor",
            *pw::keys::MEDIA_NAME => "Peak detect",
            *pw::keys::APP_NAME => "Quickshell Peak Detect",
            "stream.monitor" => "true",
            "stream.capture.sink" => if sink { "true" } else { "false" },
            "target.object" => target.as_str(),
        };
        let Ok(stream) = pw::stream::StreamRc::new(c.core.clone(), "quickshell-peak-monitor", props) else { return };
        let Ok(listener) = stream
            .add_local_listener_with_user_data(self.peak_value.clone())
            .state_changed(|_, peak, old, new| {
                // PwPeakStream::handleStateChanged: paused is silence (the
                // mic went away); so is an error - the meter does not freeze.
                let paused = new == pw::stream::StreamState::Paused && old != pw::stream::StreamState::Paused;
                if paused || matches!(new, pw::stream::StreamState::Error(_)) {
                    peak.set(0.0);
                }
            })
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
        let obj = Value::Object(Object { type_: pw::spa::sys::SPA_TYPE_OBJECT_Format, id: pw::spa::sys::SPA_PARAM_EnumFormat, properties: info.into() });
        let Ok(bytes) = pw::spa::pod::serialize::PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &obj).map(|r| r.0.into_inner()) else { return };
        let Some(pod) = Pod::from_bytes(&bytes) else { return };
        let mut params = [pod];
        if stream.connect(pw::spa::utils::Direction::Input, None, pw::stream::StreamFlags::AUTOCONNECT | pw::stream::StreamFlags::MAP_BUFFERS, &mut params).is_ok() {
            c.peak = Some(Peak { node: id, _listener: listener, _stream: stream });
        }
    }

    /// PwNodePeakMonitor.peak: the cube root of the sample peak (the scale
    /// the volumes are on), undone by the node's own volume unless that volume
    /// is the card's route (PwNode::shouldUseDevice), as quickshell does.
    pub fn peak(&self) -> f32 {
        let Some(id) = self.conn.borrow().as_ref().and_then(|c| c.peak.as_ref()).map(|p| p.node) else { return 0.0 };
        let mut v = self.peak_value.get().cbrt();
        let s = self.state.borrow();
        if s.nodes.get(&id).map_or(true, |n| on_device(&s, &n.0).is_none()) {
            if let Some(a) = s.vols.get(&id).map(Vol::audio).filter(|a| a.ready && a.volume != 0.0) {
                v /= a.volume;
            }
        }
        v
    }
}

impl Drop for Pw {
    fn drop(&mut self) {
        self.teardown();
    }
}

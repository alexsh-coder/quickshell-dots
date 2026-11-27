// Posts "cursorshape>>NAME" on Hyprland's event socket whenever the cursor shape changes,
// "cursorshape>>" when a client draws its own cursor, and "cursorclick>>1"/"0" on button press/release.
// With `hyprctl cursorpop 1` a press also plays the theme's pop_<shape> cursor (Rice-Fluent has them)
#define WLR_USE_UNSTABLE
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/ipc/s1/S1.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/pointer/cursor/CursorManager.hpp>
#include <hyprland/src/Compositor.hpp>

using Pointer::Cursor::CCursorManager;

static HANDLE        handle;
static CFunctionHook* nameHook;
static CFunctionHook* surfaceHook;
static std::string    last = "-";
static CHyprSignalListener clickListener;
static CCursorManager*     manager;
static bool                popOn;
static SP<IPC::Socket1::SCommand> popCommand;
// Back to the plain pointer waits a moment, so brushing past a link's edge doesn't flicker
static constexpr int       SETTLE = 70;
static wl_event_source*    settleTimer;
static std::string         pending;

static void post(const std::string& name) {
    if (name == last)
        return;
    last = name;
    IPC::Socket2::sock()->postEvent({"cursorshape", name});
}

using NameFn    = void (*)(CCursorManager*, const std::string&);
using SurfaceFn = void (*)(CCursorManager*, SP<Desktop::View::CWLSurface>, const Vector2D&);

static bool plain(const std::string& name) {
    return name == "left_ptr" || name == "default" || name == "arrow" || name == "top_left_arrow";
}

static int settle(void*) {
    if (!pending.empty() && manager) {
        ((NameFn)nameHook->m_original)(manager, pending);
        post(pending);
    }
    pending.clear();
    return 0;
}

static void onName(CCursorManager* self, const std::string& name) {
    manager = self;
    if (plain(name) && !plain(last) && !last.empty() && last != "-") {
        if (pending.empty())
            wl_event_source_timer_update(settleTimer, SETTLE);
        pending = name;
        return;
    }
    // Back on the same shape before it settled: nothing changed on screen
    const bool resumed = !pending.empty() && name == last;
    pending.clear();
    wl_event_source_timer_update(settleTimer, 0);
    if (resumed)
        return;
    ((NameFn)nameHook->m_original)(self, name);
    post(name);
}

static void onSurface(CCursorManager* self, SP<Desktop::View::CWLSurface> surf, const Vector2D& hotspot) {
    pending.clear();
    wl_event_source_timer_update(settleTimer, 0);
    ((SurfaceFn)surfaceHook->m_original)(self, surf, hotspot);
    post("");
}

static CFunctionHook* hook(const std::string& name, void* fn) {
    for (auto& m : HyprlandAPI::findFunctionsByName(handle, name))
        if (m.demangled.contains("CCursorManager::" + name)) {
            auto h = HyprlandAPI::createFunctionHook(handle, m.address, fn);
            h->hook();
            return h;
        }
    throw std::runtime_error("cursorshape: " + name + " not found");
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    handle = h;
    if (std::string{__hyprland_api_get_hash()} != std::string{__hyprland_api_get_client_hash()})
        throw std::runtime_error("cursorshape: built for another Hyprland, rebuild it");
    settleTimer = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, settle, nullptr);
    nameHook    = hook("setCursorFromName", (void*)&onName);
    surfaceHook = hook("setCursorSurface", (void*)&onSurface);
    clickListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) {
        const bool down = e.state == WL_POINTER_BUTTON_STATE_PRESSED;
        IPC::Socket2::sock()->postEvent({"cursorclick", down ? "1" : "0"});
        // Straight to the original: the pop isn't a shape change of its own
        if (down && popOn && manager && !last.empty() && last != "-")
            ((NameFn)nameHook->m_original)(manager, "pop_" + last);
    });
    popCommand = HyprlandAPI::registerHyprCtlCommand(handle, {"cursorpop", IPC::Socket1::COMMAND_MATCH_PREFIX, [](const IPC::Socket1::SRequest& req) {
        popOn = req.command.ends_with("1");
        return IPC::Socket1::SResponse{"ok"};
    }});
    return {"cursorshape", "Cursor shape changes as IPC events", "rice", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    clickListener.reset();
    wl_event_source_remove(settleTimer);
}

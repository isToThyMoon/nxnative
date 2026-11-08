// Host lifecycle: graceful exit (SIGTERM; on iOS the App termination callback calls dm_host_shutdown).
// Pause audio, suspend graphics (wait for in-flight NVN calls to end and drain GPU work), then _exit(0); a 1.5 s fallback goes straight to _exit(0).
// The default action also exits in about 0.08 s (exit code 143); the value of this function is stopping background threads in order, exit code 0, and giving the iOS lifecycle callback an entry.
#include "hle.h"
#include <dispatch/dispatch.h>
#include <stdatomic.h>
#include <signal.h>
#include <unistd.h>
void hlecount_flush(void); void dm_rec_finish(void);
void dm_host_shutdown_then(const char *why, void (*then)(void *), void *arg) {
    static _Atomic int once; if (atomic_exchange(&once, 1)) return;
    uint64_t t0 = now_ns(); LOG("received %s: graceful exit", why);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        LOG("[RED] graceful exit not done in 1.5 seconds, exiting at once"); if (then) then(arg); _exit(0); });
    hlecount_flush();                               // DM_HLECOUNT: _exit does not run atexit, write a copy here
    dm_rec_finish();                                // DM_REC: the held state and the buffered steps (hle_hid.c)
    dm_cheats_exit();                               // a clean exit: no safe mode for the cheats at the next launch (atexit does not run either)
    dm_audio_suspend(1);
    dm_gfx_suspend(1);
    { int64_t left = 1300 - (int64_t)((now_ns() - t0) / 1000000); dm_gfx_quit(left > 0 ? (int)left : 0); }   // the pipeline archive's unwritten captures, within the 1.5 s
    LOG("graceful exit done (%.3f s)", (now_ns() - t0) / 1e9);
    if (then) then(arg);
    _exit(0);
}
void dm_host_shutdown(const char *why) { dm_host_shutdown_then(why, NULL, NULL); }
static dispatch_source_t g_term_src;
void dm_term_install(void) {
    signal(SIGTERM, SIG_IGN);                       // do not take the default action: hand over to the GCD signal source to wrap up on an ordinary thread
    if (g_term_src) { dispatch_source_cancel(g_term_src); g_term_src = NULL; }
    g_term_src = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
    dispatch_source_set_event_handler(g_term_src, ^{ dm_host_shutdown("SIGTERM"); });
    dispatch_resume(g_term_src);
}
void dm_vsync_stop_all(void);
void dm_audio_stop_all(void);
void dm_threads_park_all(void);
void dm_guest_memory_release(int unmap_as);
void dm_modules_teardown(void);
__attribute__((weak)) void dm_audren_stop_all(void) {}
__attribute__((weak)) void dm_audren_teardown_post(void) {}
__attribute__((weak)) void dm_movie_stop_all(void) {}
__attribute__((weak)) void dm_movie_teardown_post(void) {}
__attribute__((weak)) void dm_save_sync_stop(void) {}
__attribute__((weak)) void dm_haptics_apple_teardown(void) {}
__attribute__((weak)) void dm_gfx_teardown(void) {}
__attribute__((weak)) void dm_fs_teardown(void) {}
__attribute__((weak)) void dm_ue_malloc_teardown(void) {}
__attribute__((weak)) void dm_guest_clock_wake_teardown(void) {}
void dm_host_teardown_for_shell(void) {
    if (g_term_src) { dispatch_source_cancel(g_term_src); g_term_src = NULL; }
    dm_cheats_exit();
    dm_vsync_stop_all();
    dm_audren_stop_all();
    dm_audio_stop_all();
    dm_movie_stop_all();
    dm_save_sync_stop();
    dm_haptics_apple_teardown();
    dm_guest_clock_wake_teardown();
    dm_gfx_suspend(1);
    dm_threads_park_all();
    dm_audren_teardown_post();
    dm_movie_teardown_post();
    dm_gfx_teardown();
    dm_fs_teardown();
    dm_guest_memory_release(1);
    dm_ue_malloc_teardown();
    dm_modules_teardown();
    LOG("host torn down for shell game switch");
}

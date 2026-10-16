/* Drive the normal application path with keyboard and quit events.
 * Used only by test_high_score.py through LD_PRELOAD on Linux. */
#define _GNU_SOURCE
#include <SDL3/SDL.h>
#include <dlfcn.h>
#include <string.h>

static Uint64 frame;
static SDL_WindowID window_id;
static bool started;
static bool finished;

bool SDL_RenderPresent(SDL_Renderer *renderer) {
    static bool (*present)(SDL_Renderer *);
    if (!present) present = dlsym(RTLD_NEXT, "SDL_RenderPresent");
    if (!present) return SDL_SetError("Cannot find SDL_RenderPresent for the score test");
    window_id = SDL_GetWindowID(SDL_GetRenderWindow(renderer));
    bool result = present(renderer);
    frame++;
    return result;
}

bool SDL_PollEvent(SDL_Event *event) {
    static bool (*poll)(SDL_Event *);
    if (!poll) poll = dlsym(RTLD_NEXT, "SDL_PollEvent");
    if (!poll || !event) return poll ? poll(event) : false;
    if (!started && frame >= 1) {
        memset(event, 0, sizeof(*event));
        event->type = SDL_EVENT_KEY_DOWN;
        event->key.windowID = window_id;
        event->key.scancode = SDL_SCANCODE_RETURN;
        event->key.key = SDLK_RETURN;
        event->key.down = true;
        started = true;
        return true;
    }
    if (!finished && frame >= 210) {
        memset(event, 0, sizeof(*event));
        event->type = SDL_EVENT_QUIT;
        finished = true;
        return true;
    }
    return poll(event);
}

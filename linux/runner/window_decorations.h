#ifndef PHOTOSIM_WINDOW_DECORATIONS_H_
#define PHOTOSIM_WINDOW_DECORATIONS_H_

#include <glib.h>

inline gboolean photosim_hide_header_bar() {
  const gchar* compositor_variables[] = {"HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET"};
  for (const auto* name : compositor_variables) {
    const gchar* value = g_getenv(name);
    if (value != nullptr && *value != '\0') return TRUE;
  }
  const gchar* desktop_variables[] = {
      "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION"};
  for (const auto* name : desktop_variables) {
    const gchar* value = g_getenv(name);
    if (value == nullptr) continue;
    g_auto(GStrv) desktops = g_strsplit(value, ":", -1);
    for (gchar** desktop = desktops; *desktop != nullptr; ++desktop) {
      const gchar* token = g_strstrip(*desktop);
      if (g_ascii_strcasecmp(token, "Hyprland") == 0 ||
          g_ascii_strcasecmp(token, "niri") == 0) {
        return TRUE;
      }
    }
  }
  return FALSE;
}

#endif  // PHOTOSIM_WINDOW_DECORATIONS_H_

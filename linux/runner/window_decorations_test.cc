#include <initializer_list>

#include "window_decorations.h"

int main() {
  const gchar* variables[] = {"HYPRLAND_INSTANCE_SIGNATURE", "NIRI_SOCKET",
                             "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
                             "DESKTOP_SESSION"};
  const auto reset = [&]() {
    for (const auto* name : variables) g_unsetenv(name);
  };
  reset();
  g_assert_false(photosim_hide_header_bar());
  for (const auto* name : variables) {
    reset();
    g_setenv(name, "", TRUE);
    g_assert_false(photosim_hide_header_bar());
  }
  for (const auto* name : {variables[0], variables[1]}) {
    reset();
    g_setenv(name, "/run/user/1000/compositor-socket", TRUE);
    g_assert_true(photosim_hide_header_bar());
  }
  for (const auto* name : {variables[2], variables[3], variables[4]}) {
    for (const auto* value : {"Hyprland", "niri", "GNOME:HyPrLaNd", " nIrI : GNOME"}) {
      reset();
      g_setenv(name, value, TRUE);
      g_assert_true(photosim_hide_header_bar());
    }
    for (const auto* value : {"GNOME", "KDE", "sway", "not-niri", "Hyprland-test"}) {
      reset();
      g_setenv(name, value, TRUE);
      g_assert_false(photosim_hide_header_bar());
    }
  }
  return 0;
}

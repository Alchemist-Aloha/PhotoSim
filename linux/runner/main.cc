#include "my_application.h"

int main(int argc, char** argv) {
  // Native Wayland can stop presenting Flutter GPU frames on NVIDIA; prefer XWayland.
  gdk_set_allowed_backends("x11,wayland,*");
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}

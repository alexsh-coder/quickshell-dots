cursorshape.so: main.cpp /usr/include/hyprland/src/version.h
	$(CXX) -shared -fPIC -std=c++2b -O2 $< -o $@ `pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon`

clean:
	rm -f cursorshape.so

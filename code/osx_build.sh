mkdir -p ../build

# Build platform-independent code as a shared library
clang++ \
    ./code/handmade.cpp \
    -g \
    -Wall -Werror -Wfatal-errors -pedantic \
    -Wno-gnu-anonymous-struct -Wno-nested-anon-types -Wno-c++11-compat-deprecated-writable-strings -Wno-unused-variable -Wno-unused-function -Wno-missing-braces \
    -DHANDMADE_INTERNAL=1 \
    -std=c++11 -stdlib=libc++ \
    -dynamiclib -o ../build/handmade.dylib

# Build OSX platform layer code as an executable
clang \
    ./code/osx_handmade.m \
    -g \
    -Wall -Werror -Wfatal-errors -pedantic \
    -Wno-c11-extensions -Wno-unused-variable -Wno-unused-function \
    -DHANDMADE_INTERNAL=1 \
    -framework Cocoa -framework OpenGL -framework CoreAudio -framework AudioUnit -framework IOKit \
    -o ../build/osx_handmade.out

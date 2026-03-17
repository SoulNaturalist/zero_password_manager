cmake_minimum_required(VERSION 3.18.1)
project("securewipe" VERSION 1.0.0)

# ---------------------------------------------------------------------------
# Build the securewipe shared library from C++ sources.
# ---------------------------------------------------------------------------
add_library(
    securewipe
    SHARED
    src/main/cpp/securewipe.cpp
)

# Link against the Android log library (for future debug logging if needed)
find_library(log-lib log)
target_link_libraries(securewipe ${log-lib})

# ---------------------------------------------------------------------------
# Compiler flags:
#   -fno-builtin-memset   prevents the compiler from replacing our
#                         secure_zero loop with a no-op "optimised" memset.
#   -O2                   normal optimisation (dead-store elimination is
#                         blocked by the volatile pointer technique).
# ---------------------------------------------------------------------------
target_compile_options(securewipe PRIVATE
    -fno-builtin-memset
    -O2
    -Wall
    -Wextra
)

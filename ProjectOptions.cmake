include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


include(CheckCXXSourceCompiles)


macro(sim_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)

    message(STATUS "Sanity checking UndefinedBehaviorSanitizer, it should be supported on this platform")
    set(TEST_PROGRAM "int main() { return 0; }")

    # Check if UndefinedBehaviorSanitizer works at link time
    set(CMAKE_REQUIRED_FLAGS "-fsanitize=undefined")
    set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=undefined")
    check_cxx_source_compiles("${TEST_PROGRAM}" HAS_UBSAN_LINK_SUPPORT)

    if(HAS_UBSAN_LINK_SUPPORT)
      message(STATUS "UndefinedBehaviorSanitizer is supported at both compile and link time.")
      set(SUPPORTS_UBSAN ON)
    else()
      message(WARNING "UndefinedBehaviorSanitizer is NOT supported at link time.")
      set(SUPPORTS_UBSAN OFF)
    endif()
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    if (NOT WIN32)
      message(STATUS "Sanity checking AddressSanitizer, it should be supported on this platform")
      set(TEST_PROGRAM "int main() { return 0; }")

      # Check if AddressSanitizer works at link time
      set(CMAKE_REQUIRED_FLAGS "-fsanitize=address")
      set(CMAKE_REQUIRED_LINK_OPTIONS "-fsanitize=address")
      check_cxx_source_compiles("${TEST_PROGRAM}" HAS_ASAN_LINK_SUPPORT)

      if(HAS_ASAN_LINK_SUPPORT)
        message(STATUS "AddressSanitizer is supported at both compile and link time.")
        set(SUPPORTS_ASAN ON)
      else()
        message(WARNING "AddressSanitizer is NOT supported at link time.")
        set(SUPPORTS_ASAN OFF)
      endif()
    else()
      set(SUPPORTS_ASAN ON)
    endif()
  endif()
endmacro()

macro(sim_setup_options)
  option(sim_ENABLE_HARDENING "Enable hardening" ON)
  option(sim_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    sim_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    sim_ENABLE_HARDENING
    OFF)

  sim_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR sim_PACKAGING_MAINTAINER_MODE)
    option(sim_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(sim_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(sim_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sim_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sim_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sim_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(sim_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(sim_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sim_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(sim_ENABLE_IPO "Enable IPO/LTO" ON)
    option(sim_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(sim_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(sim_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(sim_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(sim_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(sim_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(sim_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(sim_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(sim_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(sim_ENABLE_PCH "Enable precompiled headers" OFF)
    option(sim_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      sim_ENABLE_IPO
      sim_WARNINGS_AS_ERRORS
      sim_ENABLE_USER_LINKER
      sim_ENABLE_SANITIZER_ADDRESS
      sim_ENABLE_SANITIZER_LEAK
      sim_ENABLE_SANITIZER_UNDEFINED
      sim_ENABLE_SANITIZER_THREAD
      sim_ENABLE_SANITIZER_MEMORY
      sim_ENABLE_UNITY_BUILD
      sim_ENABLE_CLANG_TIDY
      sim_ENABLE_CPPCHECK
      sim_ENABLE_COVERAGE
      sim_ENABLE_PCH
      sim_ENABLE_CACHE)
  endif()

  sim_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (sim_ENABLE_SANITIZER_ADDRESS OR sim_ENABLE_SANITIZER_THREAD OR sim_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(sim_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(sim_global_options)
  if(sim_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    sim_enable_ipo()
  endif()

  sim_supports_sanitizers()

  if(sim_ENABLE_HARDENING AND sim_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sim_ENABLE_SANITIZER_UNDEFINED
       OR sim_ENABLE_SANITIZER_ADDRESS
       OR sim_ENABLE_SANITIZER_THREAD
       OR sim_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${sim_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${sim_ENABLE_SANITIZER_UNDEFINED}")
    sim_enable_hardening(sim_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(sim_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(sim_warnings INTERFACE)
  add_library(sim_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  sim_set_project_warnings(
    sim_warnings
    ${sim_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(sim_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    sim_configure_linker(sim_options)
  endif()

  include(cmake/Sanitizers.cmake)
  sim_enable_sanitizers(
    sim_options
    ${sim_ENABLE_SANITIZER_ADDRESS}
    ${sim_ENABLE_SANITIZER_LEAK}
    ${sim_ENABLE_SANITIZER_UNDEFINED}
    ${sim_ENABLE_SANITIZER_THREAD}
    ${sim_ENABLE_SANITIZER_MEMORY})

  set_target_properties(sim_options PROPERTIES UNITY_BUILD ${sim_ENABLE_UNITY_BUILD})

  if(sim_ENABLE_PCH)
    target_precompile_headers(
      sim_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(sim_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    sim_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(sim_ENABLE_CLANG_TIDY)
    sim_enable_clang_tidy(sim_options ${sim_WARNINGS_AS_ERRORS})
  endif()

  if(sim_ENABLE_CPPCHECK)
    sim_enable_cppcheck(${sim_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(sim_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    sim_enable_coverage(sim_options)
  endif()

  if(sim_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(sim_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(sim_ENABLE_HARDENING AND NOT sim_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR sim_ENABLE_SANITIZER_UNDEFINED
       OR sim_ENABLE_SANITIZER_ADDRESS
       OR sim_ENABLE_SANITIZER_THREAD
       OR sim_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    sim_enable_hardening(sim_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()

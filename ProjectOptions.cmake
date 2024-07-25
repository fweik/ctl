include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(ctl_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(ctl_setup_options)
  option(ctl_ENABLE_HARDENING "Enable hardening" ON)
  option(ctl_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    ctl_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    ctl_ENABLE_HARDENING
    OFF)

  ctl_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR ctl_PACKAGING_MAINTAINER_MODE)
    option(ctl_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(ctl_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(ctl_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ctl_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ctl_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ctl_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(ctl_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(ctl_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ctl_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(ctl_ENABLE_IPO "Enable IPO/LTO" ON)
    option(ctl_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(ctl_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(ctl_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(ctl_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(ctl_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(ctl_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(ctl_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(ctl_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(ctl_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(ctl_ENABLE_PCH "Enable precompiled headers" OFF)
    option(ctl_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      ctl_ENABLE_IPO
      ctl_WARNINGS_AS_ERRORS
      ctl_ENABLE_USER_LINKER
      ctl_ENABLE_SANITIZER_ADDRESS
      ctl_ENABLE_SANITIZER_LEAK
      ctl_ENABLE_SANITIZER_UNDEFINED
      ctl_ENABLE_SANITIZER_THREAD
      ctl_ENABLE_SANITIZER_MEMORY
      ctl_ENABLE_UNITY_BUILD
      ctl_ENABLE_CLANG_TIDY
      ctl_ENABLE_CPPCHECK
      ctl_ENABLE_COVERAGE
      ctl_ENABLE_PCH
      ctl_ENABLE_CACHE)
  endif()

  ctl_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (ctl_ENABLE_SANITIZER_ADDRESS OR ctl_ENABLE_SANITIZER_THREAD OR ctl_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(ctl_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(ctl_global_options)
  if(ctl_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    ctl_enable_ipo()
  endif()

  ctl_supports_sanitizers()

  if(ctl_ENABLE_HARDENING AND ctl_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ctl_ENABLE_SANITIZER_UNDEFINED
       OR ctl_ENABLE_SANITIZER_ADDRESS
       OR ctl_ENABLE_SANITIZER_THREAD
       OR ctl_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${ctl_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${ctl_ENABLE_SANITIZER_UNDEFINED}")
    ctl_enable_hardening(ctl_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(ctl_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(ctl_warnings INTERFACE)
  add_library(ctl_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  ctl_set_project_warnings(
    ctl_warnings
    ${ctl_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(ctl_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    ctl_configure_linker(ctl_options)
  endif()

  include(cmake/Sanitizers.cmake)
  ctl_enable_sanitizers(
    ctl_options
    ${ctl_ENABLE_SANITIZER_ADDRESS}
    ${ctl_ENABLE_SANITIZER_LEAK}
    ${ctl_ENABLE_SANITIZER_UNDEFINED}
    ${ctl_ENABLE_SANITIZER_THREAD}
    ${ctl_ENABLE_SANITIZER_MEMORY})

  set_target_properties(ctl_options PROPERTIES UNITY_BUILD ${ctl_ENABLE_UNITY_BUILD})

  if(ctl_ENABLE_PCH)
    target_precompile_headers(
      ctl_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(ctl_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    ctl_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(ctl_ENABLE_CLANG_TIDY)
    ctl_enable_clang_tidy(ctl_options ${ctl_WARNINGS_AS_ERRORS})
  endif()

  if(ctl_ENABLE_CPPCHECK)
    ctl_enable_cppcheck(${ctl_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(ctl_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    ctl_enable_coverage(ctl_options)
  endif()

  if(ctl_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(ctl_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(ctl_ENABLE_HARDENING AND NOT ctl_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR ctl_ENABLE_SANITIZER_UNDEFINED
       OR ctl_ENABLE_SANITIZER_ADDRESS
       OR ctl_ENABLE_SANITIZER_THREAD
       OR ctl_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    ctl_enable_hardening(ctl_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()

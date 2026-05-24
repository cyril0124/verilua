import os
import glob
from conan import ConanFile
from conan.tools.cmake import CMake, CMakeToolchain, cmake_layout
from conan.tools.files import get, copy, patch


class SlangConan(ConanFile):
    name = "slang"
    version = "10.0"
    license = "MIT"
    url = "https://github.com/MikePopoloski/slang"
    description = "SystemVerilog compiler and language services"
    settings = "os", "compiler", "build_type", "arch"
    options = {"shared": [True, False], "fPIC": [True, False]}
    default_options = {"shared": False, "fPIC": True}
    generators = "CMakeDeps"

    def export_sources(self):
        # Copy patches from the project-level scripts/patches/ directory into conan cache
        patches_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "..", "..", "patches")
        if os.path.isdir(patches_dir):
            copy(self, "*.patch", src=patches_dir,
                 dst=os.path.join(self.export_sources_folder, "patches"))

    def source(self):
        get(self, "https://github.com/MikePopoloski/slang/archive/refs/tags/v10.0.tar.gz",
            strip_root=True)
        self._apply_patches()

    def _apply_patches(self):
        """Apply Verilua-specific patches in sorted order."""
        patches_dir = os.path.join(self.export_sources_folder, "patches")
        if not os.path.isdir(patches_dir):
            # Fallback: patches next to conanfile (local development)
            patches_dir = os.path.join(self.recipe_folder, "..", "..", "patches")
        if os.path.isdir(patches_dir):
            patch_files = sorted(glob.glob(os.path.join(patches_dir, "*.patch")))
            for pf in patch_files:
                self.output.info(f"Applying patch: {os.path.basename(pf)}")
                patch(self, patch_file=pf)

    def layout(self):
        cmake_layout(self)

    def generate(self):
        tc = CMakeToolchain(self)
        tc.variables["SLANG_INCLUDE_TOOLS"] = "OFF"
        tc.variables["SLANG_INCLUDE_TESTS"] = "OFF"
        tc.variables["SLANG_USE_MIMALLOC"] = "ON"
        tc.variables["CMAKE_POSITION_INDEPENDENT_CODE"] = "ON"
        tc.variables["BUILD_SHARED_LIBS"] = "ON" if self.options.shared else "OFF"
        tc.generate()

    def build(self):
        cmake = CMake(self)
        cmake.configure()
        cmake.build()

    def package(self):
        cmake = CMake(self)
        cmake.install()
        if hasattr(self, "output_folder"):
            copy(self, "*.h", src=f"{self.package_folder}/include", dst=f"{self.output_folder}/include")
            copy(self, "*.a", src=f"{self.package_folder}/lib", dst=f"{self.output_folder}/lib", keep_path=False)
            copy(self, "*.so", src=f"{self.package_folder}/lib", dst=f"{self.output_folder}/lib", keep_path=False)
            copy(self, "*.lib", src=f"{self.package_folder}/lib", dst=f"{self.output_folder}/lib", keep_path=False)
            copy(self, "*.dylib", src=f"{self.package_folder}/lib", dst=f"{self.output_folder}/lib", keep_path=False)
            copy(self, "*.dll", src=f"{self.package_folder}/bin", dst=f"{self.output_folder}/bin", keep_path=False)

    def package_info(self):
        self.cpp_info.libs = ["svlang"]
        self.cpp_info.set_property("cmake_target_name", "slang::slang")

from conan import ConanFile
from conan.tools.cmake import CMake, CMakeToolchain, cmake_layout
from conan.tools.files import get, copy

class SlangConan(ConanFile):
    name = "slang"
    version = "8.0"
    license = "MIT"
    url = "https://github.com/cyril0124/slang"
    description = "SystemVerilog compiler and language services"
    settings = "os", "compiler", "build_type", "arch"
    options = {"shared": [True, False], "fPIC": [True, False]}
    default_options = {"shared": False, "fPIC": True}
    generators = "CMakeDeps"

    def source(self):
        get(self, "https://github.com/cyril0124/slang/archive/refs/tags/v8.0.tar.gz",
            strip_root=True)

    def layout(self):
        cmake_layout(self)

    def generate(self):
        tc = CMakeToolchain(self)
        tc.variables["SLANG_INCLUDE_TOOLS"] = "OFF"
        tc.variables["SLANG_INCLUDE_TESTS"] = "OFF"
        tc.variables["SLANG_USE_MIMALLOC"] = "ON"
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
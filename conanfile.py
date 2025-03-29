from conan import ConanFile
from conan.tools.files import copy, rmdir, rm

class VeriluaConan(ConanFile):
    name = "verilua"
    version = "1.0"
    settings = "os", "compiler", "build_type", "arch"

    requires = (
        "slang/8.0",
        "sol2/3.3.1",
        "argparse/3.1",
        "elfio/3.12",
        "inja/3.4.0",
        "libassert/2.1.4",
        "fmt/11.1.4",
        "mimalloc/2.1.9"
    )

    def generate(self):
        output_folder = self.generators_folder

        rmdir(self, f"{output_folder}")

        for dep in self.dependencies.values():
            dep_folder = dep.package_folder
            copy(self, "*.h", src=f"{dep_folder}/include", dst=f"{output_folder}/include", keep_path=True)
            copy(self, "*.hpp", src=f"{dep_folder}/include", dst=f"{output_folder}/include", keep_path=True)

            copy(self, "*.h", src=f"{dep_folder}/debug/include", dst=f"{output_folder}/debug/include", keep_path=True)
            copy(self, "*.hpp", src=f"{dep_folder}/debug/include", dst=f"{output_folder}/debug/include", keep_path=True)

            copy(self, "*.a", src=f"{dep_folder}/lib", dst=f"{output_folder}/lib", keep_path=False)
            copy(self, "*.so", src=f"{dep_folder}/lib", dst=f"{output_folder}/lib", keep_path=False)
            copy(self, "*.lib", src=f"{dep_folder}/lib", dst=f"{output_folder}/lib", keep_path=False)
            copy(self, "*.dylib", src=f"{dep_folder}/lib", dst=f"{output_folder}/lib", keep_path=False)
            copy(self, "*.dll", src=f"{dep_folder}/bin", dst=f"{output_folder}/bin", keep_path=False)

            copy(self, "*.a", src=f"{dep_folder}/debug/lib", dst=f"{output_folder}/debug/lib", keep_path=False)
            copy(self, "*.so", src=f"{dep_folder}/debug/lib", dst=f"{output_folder}/debug/lib", keep_path=False)
            copy(self, "*.lib", src=f"{dep_folder}/debug/lib", dst=f"{output_folder}/debug/lib", keep_path=False)
            copy(self, "*.dylib", src=f"{dep_folder}/debug/lib", dst=f"{output_folder}/debug/lib", keep_path=False)
            copy(self, "*.dll", src=f"{dep_folder}/debug/bin", dst=f"{output_folder}/debug/bin", keep_path=False)

        rm(self, "lua*.h", folder=f"{output_folder}/include")
        rm(self, "lua*.hpp", folder=f"{output_folder}/include")
        rm(self, "lauxlib.h", folder=f"{output_folder}/include")

        rm(self, "lua*.h", folder=f"{output_folder}/debug/include")
        rm(self, "lua*.hpp", folder=f"{output_folder}/debug/include")
        rm(self, "lauxlib.h", folder=f"{output_folder}/debug/include")


    def package_info(self):
        self.cpp_info.libdirs = ["lib"]
        self.cpp_info.includedirs = ["include"]
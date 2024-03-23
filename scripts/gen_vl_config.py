import argparse
import pyslang

parser = argparse.ArgumentParser(description='A script used for automately generate vpi config file.')
parser.add_argument('--file', '-f', dest="file", type=str, help='input verilog file')
parser.add_argument('--verbose', '-v', dest="verbose", action='store_true', help='verbose')


args = parser.parse_args()

verbose           = args.verbose
design_file       = args.file
assert design_file != None, "you should use <--file> to point out the design file"
files = ["TestTop.v", "tb_top.sv"]


c = pyslang.Compilation()
for f in files:
    tree = pyslang.SyntaxTree.fromFile(f)
    c.addSyntaxTree(tree)

r = c.getRoot().topInstances[0]
parsed_top_name = c.getRoot().topInstances[0].name
print(parsed_top_name)

symbols = []
def handle(obj):
    if isinstance(obj, pyslang.Symbol):
        symbols.append(obj)

r.visit(handle)


sig_privs   = []
sig_paths   = []
sig_modules = []
sig_names   = []
with open("vpi_learn.log", "r") as file:
    for line in file:
        str = line.strip()
        split_str = str.split()
        if len(split_str) != 2:
            continue
        
        sig_path = split_str[0]
        sig_priv = int(split_str[1].split(":")[-1])
        t = sig_path.split(".")
        sig_name = t[-1]
        sig_module = t[len(t) - 2]
        print(split_str, sig_path, sig_priv, sig_module, sig_name)
        
        sig_privs.append(sig_priv)
        sig_paths.append(sig_path)
        sig_modules.append(sig_module)
        sig_names.append(sig_name)



config_vlt = open("config.vlt", "w")

print("`verilator_config\n", file = config_vlt)
for i in range(len(sig_privs)):
    sig_priv = sig_privs[i]
    sig_name = sig_names[i]
    sig_path = sig_paths[i]
    sig_module = sig_modules[i]
    for s in symbols:
        if s.kind == pyslang.SymbolKind.Instance:
            if s.name == sig_module:
                if s.hierarchicalPath + "." + sig_name == sig_path:
                    verbose and print(f"[{i}]", s.definition.name, sig_priv, sig_name)
                    priv_str = ""
                    if sig_priv == 0:
                        priv_str = "public_flat_rd"
                    else:
                        assert sig_priv == 1, sig_priv
                        priv_str = "public_flat_rw"
                    print(f"{priv_str} -module \"{s.definition.name}\" -var \"{sig_name}\"", file = config_vlt)
                    verbose and print(f"{priv_str} -module \"{s.definition.name}\" -var \"{sig_name}\"")
                    break

config_vlt.close()

# TODO: ordering of definition names
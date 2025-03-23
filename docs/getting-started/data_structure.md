# 数据结构

在 `Verilua` 中，硬件信号通常被建模为 `Handle`，`Handle` 中主要包括了各种硬件信号相关的 Meta 信息，例如 width、hierarchy path、vpiType 等，Handle 有多种类型:

1. CallableHDL(chdl)
2. Bundle(bdl)
3. AliasBundle(abdl)
4. ProxyTableHandle(dut)
5. EventHandle(ehdl)

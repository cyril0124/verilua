# Install Verilua
本节主要介绍如何安装 Verilua，为了确保安装能够成功，需要全程确保网络环境可用。

## Prerequisites
- gcc >= 11.0（需要支持 C++20）
- 安装 [xmake](https://xmake.io/)
- 安装 [rust](https://www.rust-lang.org/tools/install)
- 安装 python3.xx (`mandatory`)
- （可选）安装 [iverilog](https://github.com/steveicarus/iverilog)
!!! type "Note"
    如果后续使用过程中需要使用到 iverilog 作为仿真后端（HVL 场景），那么就需要在安装 Verilua 之前提前安装 iverilog。

## 安装步骤(不使用 nix)
```shell
xmake install verilua
```
!!! warning "安装失败"
    如果安装过程失败了，那么可以重新执行上述命令，尝试再次安装。

## 安装步骤(使用 nix)
> TODO: WIP

## 测试安装是否成功
使用 shell 打印出 `VERILUA_HOME` 这一环境变量，如果 `VERILUA_HOME` 指向了当前的 Verilua 工程目录，那么就说明安装成功了。
也可以执行下面命令进行更完整的安装测试：
```shell
xmake run test
```
如果 Verilua 安装成功，则应该会看到 Terminal 最下面有这样的输出：
```shell title="Terminal"
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 
```

## 常见安装问题（TODO：）
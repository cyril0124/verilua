# Install Verilua
本节主要介绍如何安装 Verilua，为了确保安装能够成功，需要全程确保网络环境可用。

## Prerequisites
- gcc >= 11.0（需要支持 C++20）
- 安装 [xmake](https://xmake.io/)
- 安装 [rust](https://www.rust-lang.org/tools/install)
- 安装 python3.xx
- 根据需求安装下列硬件仿真器
    - [verilator](https://github.com/verilator/verilator)
    - [iverilog](https://github.com/steveicarus/iverilog)

        !!! danger "iverilog 版本问题"
            由于 iverilog 在 [v12_0 release 版本](https://github.com/steveicarus/iverilog/releases/tag/v12_0) 下存在 VPI 的 [cbNextSimTime 无限循环问题](https://github.com/steveicarus/iverilog/pull/1098)，会对 Verilua 的多任务调度功能造成影响。所以需要使用目前 iverilog 官方仓库下的 master 分支版本（或者叫 v13-devel 版本），这需要自行编译安装！

            安装完成后，需要设置环境变量 `IVERILOG_HOME` 指向刚刚安装的 iverilog 目录（包含 `bin` 和 `lib` 的目录）。

            ??? note "iverilog 安装命令"
                ```shell
                git clone https://github.com/steveicarus/iverilog.git
                cd iverilog
                git checkout s20250103
                sh autoconf.sh
                ./configure
                make
                sudo make install
                ```

    - Synopsys VCS

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


## 推荐的 Lua 开发插件

推荐使用[lua-language-server](https://github.com/LuaLS/lua-language-server)作为 Lua 的开发插件，可以获得更好的代码补全、跳转、类型标注的功能。
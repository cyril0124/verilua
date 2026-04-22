import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tutorialSidebar: [
    {
      type: 'doc',
      id: 'index',
      label: 'Introduction',
    },
    'navigation',
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'getting-started/install',
        'getting-started/luajit_vs_standard_lua',
        'getting-started/simple_hvl_example',
        'getting-started/simple_hse_example',
        'getting-started/simple_wal_example',
      ],
    },
    {
      type: 'category',
      label: 'How-to Guides',
      collapsed: false,
      items: [
        'how-to-guides/write_xmake_lua',
        'how-to-guides/simple_ut_env',
        'how-to-guides/oop_with_pl_class',
        'how-to-guides/emmylua_type_annotations',
        'how-to-guides/write_reusable_component',
        'how-to-guides/clock_driving',
        'how-to-guides/multi_clock_testing',
        'how-to-guides/common_lua_pitfalls',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: false,
      items: [
        {
          type: 'category',
          label: 'Data Structure',
          items: [
            'reference/data_structure/index',
            'reference/data_structure/callable_hdl',
            'reference/data_structure/bundle',
            'reference/data_structure/alias_bundle',
            'reference/data_structure/proxy_table_handle',
            'reference/data_structure/event_handle',
          ],
        },
        'reference/xmake_params',
        'reference/testbench_generate',
        'reference/global_configuration',
        'reference/simulator_control',
        'reference/multi_task',
        'reference/native_clock',
        'reference/slcp',
        'reference/queue',
        'reference/type_expect',
        'reference/bitvec',
        'reference/str_bits_utils',
        'reference/symbol_helper',
        'reference/await_time',
        'reference/special_env_variables',
        'reference/type_overview',
      ],
    },
  ],
};

export default sidebars;

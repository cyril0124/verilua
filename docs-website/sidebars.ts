import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  tutorialSidebar: [
    {
      type: 'doc',
      id: 'index',
      label: 'Introduction',
    },
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'getting-started/install',
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
        'how-to-guides/write_reusable_component',
        'how-to-guides/clock_driving',
        'how-to-guides/multi_clock_testing',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: false,
      items: [
        'reference/multi_task',
        'reference/await_time',
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
        'reference/bitvec',
        'reference/str_bits_utils',
        'reference/slcp',
        'reference/simulator_control',
        'reference/testbench_generate',
        'reference/native_clock',
        'reference/xmake_params',
        'reference/global_configuration',
        'reference/special_env_variables',
        'reference/symbol_helper',
      ],
    },
  ],
};

export default sidebars;

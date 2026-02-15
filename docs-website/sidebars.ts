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
        'how-to-guides/simple_ut_env',
        'how-to-guides/write_reusable_component',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: false,
      items: [
        'reference/multi_task',
        'reference/data_structure',
        'reference/bitvec',
        'reference/str_bits_utils',
        'reference/slcp',
        'reference/simulator_control',
        'reference/testbench_generate',
        'reference/xmake_params',
        'reference/global_configuration',
        'reference/special_env_variables',
      ],
    },
  ],
};

export default sidebars;

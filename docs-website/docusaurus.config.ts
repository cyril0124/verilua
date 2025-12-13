import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Verilua',
  tagline: 'An Open Source Versatile Framework for Efficient Hardware Verification and Analysis Using LuaJIT',
  favicon: 'img/favicon.svg',

  // Set the production url of your site here
  url: 'https://cyril0124.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/verilua/',

  // GitHub pages deployment config.
  organizationName: 'cyril0124',
  projectName: 'verilua',

  onBrokenLinks: 'warn',
  onBrokenAnchors: 'ignore',

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  // Enable MDX for admonitions
  markdown: {
    mermaid: true,
    format: 'detect',
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    }
  },

  // Local search plugin
  themes: [
    [
      require.resolve("@easyops-cn/docusaurus-search-local"),
      /** @type {import("@easyops-cn/docusaurus-search-local").PluginOptions} */
      ({
        hashed: true,
        language: ["en", "zh"],
        highlightSearchTermsOnTargetPage: true,
        explicitSearchResultPath: true,
        docsRouteBasePath: "/docs",
        indexBlog: false,
      }),
    ],
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          path: '../docs',
          sidebarPath: './sidebars.ts',
          // Please change this to your repo.
          editUrl:
            'https://github.com/cyril0124/verilua/tree/master/',
          // Enable admonitions
          admonitions: {
            keywords: ['note', 'tip', 'info', 'warning', 'danger', 'caution'],
          },
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/verilua-social-card.png',
    navbar: {
      title: 'Verilua',
      logo: {
        alt: 'Verilua Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
          position: 'left',
          label: 'Documentation',
        },
        {
          href: 'https://github.com/cyril0124/verilua',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        // {
        //   title: 'Docs',
        //   items: [
        //     {
        //       label: 'Getting Started',
        //       to: '/docs/getting-started/install',
        //     },
        //     {
        //       label: 'How-to Guides',
        //       to: '/docs/how-to-guides/simple_ut_env',
        //     },
        //     {
        //       label: 'Reference',
        //       to: '/docs/reference/multi_task',
        //     },
        //   ],
        // },
        // {
        //   title: 'Community',
        //   items: [
        //     {
        //       label: 'GitHub Discussions',
        //       href: 'https://github.com/cyril0124/verilua/discussions',
        //     },
        //     {
        //       label: 'GitHub Issues',
        //       href: 'https://github.com/cyril0124/verilua/issues',
        //     },
        //   ],
        // },
        // {
        //   title: 'More',
        //   items: [
        //     {
        //       label: 'GitHub',
        //       href: 'https://github.com/cyril0124/verilua',
        //     },
        //   ],
        // },
      ],
      copyright: `Copyright © 2023 - ${new Date().getFullYear()} Chuyu Zheng. Built with Docusaurus.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['lua', 'verilog', 'bash', 'json', 'yaml', 'toml'],
    },
    colorMode: {
      defaultMode: 'light',
      disableSwitch: false,
      respectPrefersColorScheme: true,
    },
    // Table of contents
    tableOfContents: {
      minHeadingLevel: 2,
      maxHeadingLevel: 4,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;

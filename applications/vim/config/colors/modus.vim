vim9script

# ==============================================================================
# Modus Operandi (Light) 全量カラーパレット定義
# ==============================================================================
const operandi_colors = {
  'accent-0': 'blue',
  'accent-1': 'magenta-warmer',
  'accent-2': 'cyan',
  'accent-3': 'red',
  'bg-active': '#c4c4c4',
  'bg-active-argument': 'bg-yellow-nuanced',
  'bg-active-value': 'bg-cyan-nuanced',
  'bg-added': '#c1f2d1',
  'bg-added-faint': '#d8f8e1',
  'bg-added-fringe': '#6cc06c',
  'bg-added-refine': '#aee5be',
  'bg-blue-intense': '#bfc9ff',
  'bg-blue-nuanced': '#ecedff',
  'bg-blue-subtle': '#ccdfff',
  'bg-button-active': 'bg-active',
  'bg-button-inactive': 'bg-dim',
  'bg-changed': '#ffdfa9',
  'bg-changed-faint': '#ffefbf',
  'bg-changed-fringe': '#d7c20a',
  'bg-changed-refine': '#fac090',
  'bg-clay': '#f1c8b5',
  'bg-completion': '#c0deff',
  'bg-cyan-intense': '#a4d5f9',
  'bg-cyan-nuanced': '#e0f2fa',
  'bg-cyan-subtle': '#bfefff',
  'bg-diff-context': '#f3f3f3',
  'bg-dim': '#f2f2f2',
  'bg-graph-blue-0': '#7f90ff',
  'bg-graph-blue-1': '#a6c0ff',
  'bg-graph-cyan-0': '#70d3f0',
  'bg-graph-cyan-1': '#afefff',
  'bg-graph-green-0': '#45c050',
  'bg-graph-green-1': '#75ef30',
  'bg-graph-magenta-0': '#e07fff',
  'bg-graph-magenta-1': '#fad0ff',
  'bg-graph-red-0': '#ef7969',
  'bg-graph-red-1': '#ffaab4',
  'bg-graph-yellow-0': '#ffcf00',
  'bg-graph-yellow-1': '#f9ff00',
  'bg-green-intense': '#8adf80',
  'bg-green-nuanced': '#e0f6e0',
  'bg-green-subtle': '#b3fabf',
  'bg-hl-line': '#dae5ec',
  'bg-hover': '#b2e4dc',
  'bg-hover-secondary': '#f5d0a0',
  'bg-inactive': '#e0e0e0',
  'bg-lavender': '#dfcdfa',
  'bg-line-number-active': 'bg-active',
  'bg-line-number-inactive': 'bg-dim',
  'bg-magenta-intense': '#dfa0f0',
  'bg-magenta-nuanced': '#f8e6f5',
  'bg-magenta-subtle': '#ffddff',
  'bg-main': '#ffffff',
  'bg-mark-delete': 'bg-red-subtle',
  'bg-mark-other': 'bg-yellow-subtle',
  'bg-mark-select': 'bg-cyan-subtle',
  'bg-mode-line-active': '#c8c8c8',
  'bg-mode-line-inactive': '#e6e6e6',
  'bg-ochre': '#f0e3c0',
  'bg-paren-expression': '#efd3f5',
  'bg-paren-match': '#5fcfff',
  'bg-prominent-err': 'bg-red-intense',
  'bg-prominent-note': 'bg-cyan-intense',
  'bg-prominent-warning': 'bg-yellow-intense',
  'bg-prose-block-contents': 'bg-dim',
  'bg-prose-block-delimiter': 'bg-dim',
  'bg-red-intense': '#ff8f88',
  'bg-red-nuanced': '#ffe8e8',
  'bg-red-subtle': '#ffcfbf',
  'bg-region': '#bdbdbd',
  'bg-removed': '#ffd8d5',
  'bg-removed-faint': '#ffe9e9',
  'bg-removed-fringe': '#d84a4f',
  'bg-removed-refine': '#f3b5af',
  'bg-sage': '#c0e7d4',
  'bg-search-current': 'bg-yellow-intense',
  'bg-search-lazy': 'bg-cyan-intense',
  'bg-search-replace': 'bg-red-intense',
  'bg-search-rx-group-0': 'bg-blue-intense',
  'bg-search-rx-group-1': 'bg-green-intense',
  'bg-search-rx-group-2': 'bg-red-subtle',
  'bg-search-rx-group-3': 'bg-magenta-subtle',
  'bg-space-err': 'bg-red-intense',
  'bg-tab-bar': '#dfdfdf',
  'bg-tab-current': '#ffffff',
  'bg-tab-other': '#c2c2c2',
  'bg-term-black': '#000000',
  'bg-term-black-bright': '#595959',
  'bg-term-blue': 'blue',
  'bg-term-blue-bright': 'blue-warmer',
  'bg-term-cyan': 'cyan',
  'bg-term-cyan-bright': 'cyan-cooler',
  'bg-term-green': 'green',
  'bg-term-green-bright': 'green-cooler',
  'bg-term-magenta': 'magenta',
  'bg-term-magenta-bright': 'magenta-cooler',
  'bg-term-red': 'red',
  'bg-term-red-bright': 'red-warmer',
  'bg-term-white': '#a6a6a6',
  'bg-term-white-bright': '#ffffff',
  'bg-term-yellow': 'yellow',
  'bg-term-yellow-bright': 'yellow-warmer',
  'bg-yellow-intense': '#f3d000',
  'bg-yellow-nuanced': '#f8f0d0',
  'bg-yellow-subtle': '#fff576',
  'blue': '#0031a9',
  'blue-cooler': '#0000b0',
  'blue-faint': '#003497',
  'blue-intense': '#0000ff',
  'blue-warmer': '#3548cf',
  'border': '#9f9f9f',
  'border-mode-line-active': '#5a5a5a',
  'border-mode-line-inactive': '#a3a3a3',
  'bracket': 'fg-main',
  'builtin': 'magenta-warmer',
  'comment': 'fg-dim',
  'constant': 'blue-cooler',
  'cursor': 'fg-main',
  'cyan': '#005e8b',
  'cyan-cooler': '#005f5f',
  'cyan-faint': '#005077',
  'cyan-intense': '#008899',
  'cyan-warmer': '#3f578f',
  'date-common': 'cyan',
  'date-deadline': 'red-cooler',
  'date-deadline-subtle': 'red-faint',
  'date-event': 'fg-alt',
  'date-holiday': 'red',
  'date-holiday-other': 'blue',
  'date-now': 'fg-main',
  'date-range': 'fg-alt',
  'date-scheduled': 'yellow',
  'date-scheduled-subtle': 'yellow-faint',
  'date-weekday': 'cyan',
  'date-weekend': 'magenta',
  'delimiter': 'fg-main',
  'docmarkup': 'magenta-faint',
  'docstring': 'green-faint',
  'err': 'red',
  'fg-active-argument': 'yellow-warmer',
  'fg-active-value': 'cyan-warmer',
  'fg-added': '#005000',
  'fg-added-intense': '#006700',
  'fg-alt': '#193668',
  'fg-button-active': 'fg-main',
  'fg-button-inactive': 'fg-dim',
  'fg-changed': '#553d00',
  'fg-changed-intense': '#655000',
  'fg-clay': '#63192a',
  'fg-completion-match-0': 'blue',
  'fg-completion-match-1': 'magenta-warmer',
  'fg-completion-match-2': 'cyan',
  'fg-completion-match-3': 'red',
  'fg-dim': '#595959',
  'fg-heading-0': 'cyan-cooler',
  'fg-heading-1': 'fg-main',
  'fg-heading-2': 'yellow-faint',
  'fg-heading-3': 'fg-alt',
  'fg-heading-4': 'magenta',
  'fg-heading-5': 'green-faint',
  'fg-heading-6': 'red-faint',
  'fg-heading-7': 'cyan-warmer',
  'fg-heading-8': 'fg-dim',
  'fg-lavender': '#443379',
  'fg-line-number-active': 'fg-main',
  'fg-line-number-inactive': 'fg-dim',
  'fg-link': 'blue-warmer',
  'fg-link-symbolic': 'cyan',
  'fg-link-visited': 'magenta',
  'fg-main': '#000000',
  'fg-mark-delete': 'red',
  'fg-mark-other': 'yellow',
  'fg-mark-select': 'cyan',
  'fg-mode-line-active': '#000000',
  'fg-mode-line-inactive': '#585858',
  'fg-ochre': '#573a30',
  'fg-paren-match': 'fg-main',
  'fg-prominent-err': 'fg-main',
  'fg-prominent-note': 'fg-main',
  'fg-prominent-warning': 'fg-main',
  'fg-prompt': 'cyan-cooler',
  'fg-prose-block-delimiter': 'fg-dim',
  'fg-prose-code': 'cyan-cooler',
  'fg-prose-macro': 'magenta-cooler',
  'fg-prose-verbatim': 'magenta-warmer',
  'fg-region': '#000000',
  'fg-removed': '#8f1313',
  'fg-removed-intense': '#aa2222',
  'fg-sage': '#124b41',
  'fg-space': 'border',
  'fg-term-black': '#000000',
  'fg-term-black-bright': '#595959',
  'fg-term-blue': 'blue',
  'fg-term-blue-bright': 'blue-warmer',
  'fg-term-cyan': 'cyan',
  'fg-term-cyan-bright': 'cyan-cooler',
  'fg-term-green': 'green',
  'fg-term-green-bright': 'green-cooler',
  'fg-term-magenta': 'magenta',
  'fg-term-magenta-bright': 'magenta-cooler',
  'fg-term-red': 'red',
  'fg-term-red-bright': 'red-warmer',
  'fg-term-white': '#a6a6a6',
  'fg-term-white-bright': '#ffffff',
  'fg-term-yellow': 'yellow',
  'fg-term-yellow-bright': 'yellow-warmer',
  'fnname': 'magenta',
  'fringe': 'bg-dim',
  'gold': '#80601f',
  'green': '#006800',
  'green-cooler': '#00663f',
  'green-faint': '#2a5045',
  'green-intense': '#008900',
  'green-warmer': '#316500',
  'identifier': 'yellow-cooler',
  'indigo': '#4a3a8a',
  'info': 'cyan-cooler',
  'keybind': 'blue-cooler',
  'keyword': 'magenta-cooler',
  'magenta': '#721045',
  'magenta-cooler': '#531ab6',
  'magenta-faint': '#7c318f',
  'magenta-intense': '#dd22dd',
  'magenta-warmer': '#8f0075',
  'mail-cite-0': 'blue-faint',
  'mail-cite-1': 'yellow-warmer',
  'mail-cite-2': 'cyan-cooler',
  'mail-cite-3': 'red-cooler',
  'mail-other': 'magenta-faint',
  'mail-part': 'cyan',
  'mail-recipient': 'magenta-cooler',
  'mail-subject': 'magenta-warmer',
  'maroon': '#731c52',
  'modeline-err': '#7f0000',
  'modeline-info': '#002580',
  'modeline-warning': '#5f0070',
  'name': 'magenta',
  'number': 'fg-main',
  'olive': '#56692d',
  'operator': 'fg-main',
  'pink': '#7b435c',
  'preprocessor': 'red-cooler',
  'property': 'cyan',
  'prose-done': 'green',
  'prose-metadata': 'fg-dim',
  'prose-metadata-value': 'fg-alt',
  'prose-table': 'fg-alt',
  'prose-table-formula': 'magenta-warmer',
  'prose-tag': 'magenta-faint',
  'prose-todo': 'red',
  'punctuation': 'fg-main',
  'rainbow-0': 'fg-main',
  'rainbow-1': 'magenta-intense',
  'rainbow-2': 'cyan-intense',
  'rainbow-3': 'red-warmer',
  'rainbow-4': 'yellow-intense',
  'rainbow-5': 'magenta-cooler',
  'rainbow-6': 'green-intense',
  'rainbow-7': 'blue-warmer',
  'rainbow-8': 'magenta-warmer',
  'red': '#a60000',
  'red-cooler': '#a0132f',
  'red-faint': '#7f0000',
  'red-intense': '#d00000',
  'red-warmer': '#972500',
  'rust': '#8a290f',
  'rx-backslash': 'magenta',
  'rx-construct': 'green-cooler',
  'slate': '#2f3f83',
  'string': 'blue-warmer',
  'type': 'cyan-cooler',
  'underline-err': 'red-intense',
  'underline-link': 'blue-warmer',
  'underline-link-symbolic': 'cyan',
  'underline-link-visited': 'magenta',
  'underline-note': 'cyan-intense',
  'underline-warning': 'yellow-intense',
  'variable': 'cyan',
  'warning': 'yellow-warmer',
  'yellow': '#6f5500',
  'yellow-cooler': '#7a4f2f',
  'yellow-faint': '#624416',
  'yellow-intense': '#808000',
  'yellow-warmer': '#884900',
}

# ==============================================================================
# Modus Vivendi (Dark) 全量カラーパレット定義
# ==============================================================================
const vivendi_colors = {
  'accent-0': 'blue-cooler',
  'accent-1': 'magenta-warmer',
  'accent-2': 'cyan-cooler',
  'accent-3': 'yellow',
  'bg-active': '#535353',
  'bg-active-argument': 'bg-yellow-nuanced',
  'bg-active-value': 'bg-cyan-nuanced',
  'bg-added': '#00381f',
  'bg-added-faint': '#002910',
  'bg-added-fringe': '#237f3f',
  'bg-added-refine': '#034f2f',
  'bg-blue-intense': '#1640b0',
  'bg-blue-nuanced': '#12154a',
  'bg-blue-subtle': '#242679',
  'bg-button-active': 'bg-active',
  'bg-button-inactive': 'bg-dim',
  'bg-changed': '#363300',
  'bg-changed-faint': '#2a1f00',
  'bg-changed-fringe': '#8a7a00',
  'bg-changed-refine': '#4a4a00',
  'bg-clay': '#49191a',
  'bg-completion': '#2f447f',
  'bg-cyan-intense': '#2266ae',
  'bg-cyan-nuanced': '#042837',
  'bg-cyan-subtle': '#004065',
  'bg-diff-context': '#1a1a1a',
  'bg-dim': '#1e1e1e',
  'bg-graph-blue-0': '#2fafef',
  'bg-graph-blue-1': '#1f2f8f',
  'bg-graph-cyan-0': '#47dfea',
  'bg-graph-cyan-1': '#00808f',
  'bg-graph-green-0': '#0fed00',
  'bg-graph-green-1': '#007800',
  'bg-graph-magenta-0': '#bf94fe',
  'bg-graph-magenta-1': '#5f509f',
  'bg-graph-red-0': '#b52c2c',
  'bg-graph-red-1': '#702020',
  'bg-graph-yellow-0': '#f1e00a',
  'bg-graph-yellow-1': '#b08940',
  'bg-green-intense': '#2f822f',
  'bg-green-nuanced': '#092f1f',
  'bg-green-subtle': '#00422a',
  'bg-hl-line': '#2f3849',
  'bg-hover': '#45605e',
  'bg-hover-secondary': '#654a39',
  'bg-inactive': '#303030',
  'bg-lavender': '#38325c',
  'bg-line-number-active': 'bg-active',
  'bg-line-number-inactive': 'bg-dim',
  'bg-magenta-intense': '#7030af',
  'bg-magenta-nuanced': '#2f0c3f',
  'bg-magenta-subtle': '#552f5f',
  'bg-main': '#000000',
  'bg-mark-delete': 'bg-red-subtle',
  'bg-mark-other': 'bg-yellow-subtle',
  'bg-mark-select': 'bg-cyan-subtle',
  'bg-mode-line-active': '#505050',
  'bg-mode-line-inactive': '#2d2d2d',
  'bg-ochre': '#462f20',
  'bg-paren-expression': '#453040',
  'bg-paren-match': '#2f7f9f',
  'bg-prominent-err': 'bg-red-intense',
  'bg-prominent-note': 'bg-cyan-intense',
  'bg-prominent-warning': 'bg-yellow-intense',
  'bg-prose-block-contents': 'bg-dim',
  'bg-prose-block-delimiter': 'bg-dim',
  'bg-red-intense': '#9d1f1f',
  'bg-red-nuanced': '#3a0c14',
  'bg-red-subtle': '#620f2a',
  'bg-region': '#5a5a5a',
  'bg-removed': '#4f1119',
  'bg-removed-faint': '#380a0f',
  'bg-removed-fringe': '#b81a1f',
  'bg-removed-refine': '#781a1f',
  'bg-sage': '#143e32',
  'bg-search-current': 'bg-yellow-intense',
  'bg-search-lazy': 'bg-cyan-intense',
  'bg-search-replace': 'bg-red-intense',
  'bg-search-rx-group-0': 'bg-blue-intense',
  'bg-search-rx-group-1': 'bg-green-intense',
  'bg-search-rx-group-2': 'bg-red-subtle',
  'bg-search-rx-group-3': 'bg-magenta-subtle',
  'bg-space-err': 'bg-red-intense',
  'bg-tab-bar': '#313131',
  'bg-tab-current': '#000000',
  'bg-tab-other': '#545454',
  'bg-term-black': '#000000',
  'bg-term-black-bright': '#595959',
  'bg-term-blue': 'blue',
  'bg-term-blue-bright': 'blue-warmer',
  'bg-term-cyan': 'cyan',
  'bg-term-cyan-bright': 'cyan-cooler',
  'bg-term-green': 'green',
  'bg-term-green-bright': 'green-cooler',
  'bg-term-magenta': 'magenta',
  'bg-term-magenta-bright': 'magenta-cooler',
  'bg-term-red': 'red',
  'bg-term-red-bright': 'red-warmer',
  'bg-term-white': '#a6a6a6',
  'bg-term-white-bright': '#ffffff',
  'bg-term-yellow': 'yellow',
  'bg-term-yellow-bright': 'yellow-warmer',
  'bg-yellow-intense': '#7a6100',
  'bg-yellow-nuanced': '#381d0f',
  'bg-yellow-subtle': '#4a4000',
  'blue': '#2fafff',
  'blue-cooler': '#00bcff',
  'blue-faint': '#82b0ec',
  'blue-intense': '#338fff',
  'blue-warmer': '#79a8ff',
  'border': '#646464',
  'border-mode-line-active': '#959595',
  'border-mode-line-inactive': '#606060',
  'bracket': 'fg-main',
  'builtin': 'magenta-warmer',
  'comment': 'fg-dim',
  'constant': 'blue-cooler',
  'cursor': 'fg-main',
  'cyan': '#00d3d0',
  'cyan-cooler': '#6ae4b9',
  'cyan-faint': '#9ac8e0',
  'cyan-intense': '#00eff0',
  'cyan-warmer': '#4ae2f0',
  'date-common': 'cyan',
  'date-deadline': 'red-cooler',
  'date-deadline-subtle': 'red-faint',
  'date-event': 'fg-alt',
  'date-holiday': 'magenta-warmer',
  'date-holiday-other': 'blue',
  'date-now': 'fg-main',
  'date-range': 'fg-alt',
  'date-scheduled': 'yellow-cooler',
  'date-scheduled-subtle': 'yellow-faint',
  'date-weekday': 'cyan',
  'date-weekend': 'magenta',
  'delimiter': 'fg-main',
  'docmarkup': 'magenta-faint',
  'docstring': 'cyan-faint',
  'err': 'red',
  'fg-active-argument': 'yellow-cooler',
  'fg-active-value': 'cyan-cooler',
  'fg-added': '#a0e0a0',
  'fg-added-intense': '#80e080',
  'fg-alt': '#c6daff',
  'fg-button-active': 'fg-main',
  'fg-button-inactive': 'fg-dim',
  'fg-changed': '#efef80',
  'fg-changed-intense': '#c0b05f',
  'fg-clay': '#f1b090',
  'fg-completion-match-0': 'blue-cooler',
  'fg-completion-match-1': 'magenta-warmer',
  'fg-completion-match-2': 'cyan-cooler',
  'fg-completion-match-3': 'yellow',
  'fg-dim': '#989898',
  'fg-heading-0': 'cyan-cooler',
  'fg-heading-1': 'fg-main',
  'fg-heading-2': 'yellow-faint',
  'fg-heading-3': 'blue-faint',
  'fg-heading-4': 'magenta',
  'fg-heading-5': 'green-faint',
  'fg-heading-6': 'red-faint',
  'fg-heading-7': 'cyan-faint',
  'fg-heading-8': 'fg-dim',
  'fg-lavender': '#dfc0f0',
  'fg-line-number-active': 'fg-main',
  'fg-line-number-inactive': 'fg-dim',
  'fg-link': 'blue-warmer',
  'fg-link-symbolic': 'cyan',
  'fg-link-visited': 'magenta',
  'fg-main': '#ffffff',
  'fg-mark-delete': 'red-cooler',
  'fg-mark-other': 'yellow',
  'fg-mark-select': 'cyan',
  'fg-mode-line-active': '#ffffff',
  'fg-mode-line-inactive': '#969696',
  'fg-ochre': '#e0d09c',
  'fg-paren-match': 'fg-main',
  'fg-prominent-err': 'fg-main',
  'fg-prominent-note': 'fg-main',
  'fg-prominent-warning': 'fg-main',
  'fg-prompt': 'cyan-cooler',
  'fg-prose-block-delimiter': 'fg-dim',
  'fg-prose-code': 'cyan-cooler',
  'fg-prose-macro': 'magenta-cooler',
  'fg-prose-verbatim': 'magenta-warmer',
  'fg-region': '#ffffff',
  'fg-removed': '#ffbfbf',
  'fg-removed-intense': '#ff9095',
  'fg-sage': '#c3e7d4',
  'fg-space': 'border',
  'fg-term-black': '#000000',
  'fg-term-black-bright': '#595959',
  'fg-term-blue': 'blue',
  'fg-term-blue-bright': 'blue-warmer',
  'fg-term-cyan': 'cyan',
  'fg-term-cyan-bright': 'cyan-cooler',
  'fg-term-green': 'green',
  'fg-term-green-bright': 'green-cooler',
  'fg-term-magenta': 'magenta',
  'fg-term-magenta-bright': 'magenta-cooler',
  'fg-term-red': 'red',
  'fg-term-red-bright': 'red-warmer',
  'fg-term-white': '#a6a6a6',
  'fg-term-white-bright': '#ffffff',
  'fg-term-yellow': 'yellow',
  'fg-term-yellow-bright': 'yellow-warmer',
  'fnname': 'magenta',
  'fringe': 'bg-dim',
  'gold': '#c0965b',
  'green': '#44bc44',
  'green-cooler': '#00c06f',
  'green-faint': '#88ca9f',
  'green-intense': '#44df44',
  'green-warmer': '#70b900',
  'identifier': 'yellow-faint',
  'indigo': '#9099d9',
  'info': 'cyan-cooler',
  'keybind': 'blue-cooler',
  'keyword': 'magenta-cooler',
  'magenta': '#feacd0',
  'magenta-cooler': '#b6a0ff',
  'magenta-faint': '#caa6df',
  'magenta-intense': '#ff66ff',
  'magenta-warmer': '#f78fe7',
  'mail-cite-0': 'blue-warmer',
  'mail-cite-1': 'yellow-cooler',
  'mail-cite-2': 'cyan-cooler',
  'mail-cite-3': 'red-cooler',
  'mail-other': 'magenta-faint',
  'mail-part': 'blue',
  'mail-recipient': 'magenta-cooler',
  'mail-subject': 'magenta-warmer',
  'maroon': '#cf7fa7',
  'modeline-err': '#ffa9bf',
  'modeline-info': '#9fefff',
  'modeline-warning': '#dfcf43',
  'name': 'magenta',
  'number': 'fg-main',
  'olive': '#9cbd6f',
  'operator': 'fg-main',
  'pink': '#d09dc0',
  'preprocessor': 'red-cooler',
  'property': 'cyan',
  'prose-done': 'green',
  'prose-metadata': 'fg-dim',
  'prose-metadata-value': 'fg-alt',
  'prose-table': 'fg-alt',
  'prose-table-formula': 'magenta-warmer',
  'prose-tag': 'magenta-faint',
  'prose-todo': 'red',
  'punctuation': 'fg-main',
  'rainbow-0': 'fg-main',
  'rainbow-1': 'magenta-intense',
  'rainbow-2': 'cyan-intense',
  'rainbow-3': 'red-warmer',
  'rainbow-4': 'yellow-intense',
  'rainbow-5': 'magenta-cooler',
  'rainbow-6': 'green-intense',
  'rainbow-7': 'blue-warmer',
  'rainbow-8': 'magenta-warmer',
  'red': '#ff5f59',
  'red-cooler': '#ff7f86',
  'red-faint': '#ff9580',
  'red-intense': '#ff5f5f',
  'red-warmer': '#ff6b55',
  'rust': '#db7b5f',
  'rx-backslash': 'magenta',
  'rx-construct': 'green-cooler',
  'slate': '#76afbf',
  'string': 'blue-warmer',
  'type': 'cyan-cooler',
  'underline-err': 'red-intense',
  'underline-link': 'blue-warmer',
  'underline-link-symbolic': 'cyan',
  'underline-link-visited': 'magenta',
  'underline-note': 'cyan',
  'underline-warning': 'yellow',
  'variable': 'cyan',
  'warning': 'yellow-warmer',
  'yellow': '#d0bc00',
  'yellow-cooler': '#dfaf7a',
  'yellow-faint': '#d2b580',
  'yellow-intense': '#efef00',
  'yellow-warmer': '#fec43f',
}

# ==============================================================================
# ヘルパー関数
# ==============================================================================
def Resolve(palette: dict<string>, key: string): string
  var val = key
  while has_key(palette, val)
    var next_val = palette[val]
    if next_val[0] == '#'
      return next_val
    endif
    val = next_val
  endwhile
  return val
enddef

# ==============================================================================
# 初期化処理
# ==============================================================================
highlight clear
if exists("syntax_on")
  syntax reset
endif

g:colors_name = "modus"

# ==============================================================================
# オプション設定とパレットのフラット化（動的生成）
# ==============================================================================
# ユーザー設定辞書 `g:modus_settings` を取得
var settings = get(g:, 'modus_settings', {})

# スタイル属性の取得（デフォルト値を親切に設定）
var bold_keywords = get(settings, 'bold_keywords', true) ? 'bold' : 'NONE'
var bold_types    = get(settings, 'bold_types', true) ? 'bold' : 'NONE'
var italic_comments = get(settings, 'italic_comments', false) ? 'italic' : 'NONE'

# &background に基づきベースパレットのシャローコピーを作成
var base = extend({}, &background == 'dark' ? vivendi_colors : operandi_colors)

# ユーザーによるカラーの上書き（overrides）があればマージ
if has_key(settings, 'overrides')
  extend(base, settings['overrides'])
endif

# パレット全体のエイリアスを再帰解決して完全フラット化
var syntax: dict<string> = {}
for key in keys(base)
  syntax[key] = Resolve(base, key)
endfor

# ==============================================================================
# ターミナルカラー (g:terminal_ansi_colors) の自動生成
# ==============================================================================
if has('terminal')
  var ansi_keys = [
    'bg-term-black', 'fg-term-red', 'fg-term-green', 'fg-term-yellow',
    'fg-term-blue', 'fg-term-magenta', 'fg-term-cyan', 'fg-term-white',
    'bg-term-black-bright', 'fg-term-red-bright', 'fg-term-green-bright', 'fg-term-yellow-bright',
    'fg-term-blue-bright', 'fg-term-magenta-bright', 'fg-term-cyan-bright', 'fg-term-white-bright'
  ]
  g:terminal_ansi_colors = map(ansi_keys, (_, k) => syntax[k])
endif

# ==============================================================================
# ハイライト定義 (一括解決済みなので syntax['key'] で安全＆高速にマッピング)
# ==============================================================================

# エディタ基本画面
execute $"highlight Normal guifg={syntax['fg-main']} guibg={syntax['bg-main']}"
execute $"highlight NonText guifg={syntax['fg-dim']}"
execute $"highlight EndOfBuffer guifg={syntax['fg-dim']}"

# ラインナンバー & カーソル行
execute $"highlight LineNr guifg={syntax['fg-line-number-inactive']} guibg={syntax['bg-line-number-inactive']}"
execute $"highlight CursorLineNr guifg={syntax['fg-line-number-active']} guibg={syntax['bg-line-number-active']}"
execute $"highlight CursorLine guibg={syntax['bg-hl-line']}"
execute $"highlight CursorColumn guibg={syntax['bg-hl-line']}"

# ウィンドウUI・境界線
execute $"highlight Visual guifg={syntax['fg-region']} guibg={syntax['bg-region']}"
execute $"highlight SignColumn guibg={syntax['bg-main']}"
execute $"highlight VertSplit guifg={syntax['border']} guibg={syntax['bg-main']}"
execute $"highlight WinSeparator guifg={syntax['border']} guibg={syntax['bg-main']}"
execute $"highlight ColorColumn guibg={syntax['bg-dim']}"

# ポップアップメニュー
execute $"highlight Pmenu guifg={syntax['fg-main']} guibg={syntax['bg-dim']}"
execute $"highlight PmenuSel guifg={syntax['fg-main']} guibg={syntax['bg-active']}"
execute $"highlight PmenuSbar guibg={syntax['bg-dim']}"
execute $"highlight PmenuThumb guibg={syntax['fg-dim']}"

# ステータスライン & タブライン
execute $"highlight StatusLine guifg={syntax['fg-mode-line-active']} guibg={syntax['bg-mode-line-active']} gui=bold"
execute $"highlight StatusLineNC guifg={syntax['fg-mode-line-inactive']} guibg={syntax['bg-mode-line-inactive']}"
execute $"highlight TabLine guifg={syntax['fg-dim']} guibg={syntax['bg-tab-bar']}"
execute $"highlight TabLineSel guifg={syntax['fg-main']} guibg={syntax['bg-tab-current']} gui=bold"
execute $"highlight TabLineFill guibg={syntax['bg-tab-bar']}"

# 検索・括弧マッチ
execute $"highlight Search guibg={syntax['bg-search-lazy']} guifg={syntax['fg-main']}"
execute $"highlight CurSearch guibg={syntax['bg-search-current']} guifg={syntax['fg-main']}"
execute $"highlight IncSearch guibg={syntax['bg-search-current']} guifg={syntax['fg-main']}"
execute $"highlight MatchParen guibg={syntax['bg-paren-match']} guifg={syntax['fg-paren-match']} gui=bold"

# 差分 (Diff)
execute $"highlight DiffAdd guifg={syntax['fg-added']} guibg={syntax['bg-added']}"
execute $"highlight DiffChange guifg={syntax['fg-changed']} guibg={syntax['bg-changed']}"
execute $"highlight DiffDelete guifg={syntax['fg-removed']} guibg={syntax['bg-removed']}"
execute $"highlight DiffText guifg={syntax['fg-changed-intense']} guibg={syntax['bg-changed-refine']} gui=bold"

# メッセージ・折りたたみ
execute $"highlight Folded guifg={syntax['fg-dim']} guibg={syntax['bg-dim']}"
execute $"highlight FoldColumn guifg={syntax['fg-dim']} guibg={syntax['bg-main']}"
execute $"highlight ModeMsg guifg={syntax['fg-alt']} gui=bold"
execute $"highlight MoreMsg guifg={syntax['info']}"
execute $"highlight Question guifg={syntax['info']}"
execute $"highlight WarningMsg guifg={syntax['warning']} gui=bold"
execute $"highlight ErrorMsg guifg={syntax['err']} gui=bold"

# 標準構文ハイライト (スタイル属性の動的制御)
execute $"highlight Comment guifg={syntax['comment']} gui={italic_comments}"
execute $"highlight Constant guifg={syntax['constant']}"
execute $"highlight String guifg={syntax['string']}"
execute $"highlight Character guifg={syntax['string']}"
execute $"highlight Number guifg={syntax['number']}"
execute $"highlight Boolean guifg={syntax['constant']}"
execute $"highlight Float guifg={syntax['number']}"

execute $"highlight Identifier guifg={syntax['identifier']}"
execute $"highlight Function guifg={syntax['fnname']}"

execute $"highlight Statement guifg={syntax['keyword']} gui={bold_keywords}"
execute $"highlight Conditional guifg={syntax['keyword']} gui={bold_keywords}"
execute $"highlight Repeat guifg={syntax['keyword']} gui={bold_keywords}"
execute $"highlight Label guifg={syntax['keyword']}"
execute $"highlight Operator guifg={syntax['operator']}"
execute $"highlight Keyword guifg={syntax['keyword']} gui={bold_keywords}"
execute $"highlight Exception guifg={syntax['keyword']} gui={bold_keywords}"

execute $"highlight PreProc guifg={syntax['preprocessor']}"
execute $"highlight Include guifg={syntax['preprocessor']}"
execute $"highlight Define guifg={syntax['preprocessor']}"
execute $"highlight Macro guifg={syntax['preprocessor']}"
execute $"highlight PreCondit guifg={syntax['preprocessor']}"

execute $"highlight Type guifg={syntax['type']} gui={bold_types}"
execute $"highlight StorageClass guifg={syntax['type']} gui={bold_types}"
execute $"highlight Structure guifg={syntax['type']} gui={bold_types}"
execute $"highlight Typedef guifg={syntax['type']} gui={bold_types}"

execute $"highlight Special guifg={syntax['fg-alt']}"
execute $"highlight SpecialChar guifg={syntax['fg-alt']}"
execute $"highlight Tag guifg={syntax['fg-alt']}"
execute $"highlight Delimiter guifg={syntax['delimiter']}"
execute $"highlight SpecialComment guifg={syntax['fg-dim']} gui={italic_comments}"
execute $"highlight Debug guifg={syntax['red']}"

execute $"highlight Underlined gui=underline guifg={syntax['fg-link']}"
execute $"highlight Ignore guifg={syntax['bg-main']}"
execute $"highlight Error guifg={syntax['fg-main']} guibg={syntax['bg-red-intense']}"
execute $"highlight Todo guifg={syntax['fg-main']} guibg={syntax['bg-yellow-intense']}"

# ==============================================================================
# プラグインサポート: vim-lsp
# ==============================================================================
execute $"highlight LspErrorText guifg={syntax['red']} gui=bold"
execute $"highlight LspWarningText guifg={syntax['warning']} gui=bold"
execute $"highlight LspInformationText guifg={syntax['info']}"
execute $"highlight LspHintText guifg={syntax['cyan']}"

execute $"highlight LspErrorHighlight gui=undercurl guisp={syntax['underline-err']}"
execute $"highlight LspWarningHighlight gui=undercurl guisp={syntax['underline-warning']}"
execute $"highlight LspInformationHighlight gui=undercurl guisp={syntax['underline-note']}"
execute $"highlight LspHintHighlight gui=undercurl guisp={syntax['underline-note']}"

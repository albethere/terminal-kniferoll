package main

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ─── Data ────────────────────────────────────────────────────────────────────

type item struct {
	key         string
	label       string
	description string
	checked     bool
}

var baseItems = []item{
	{
		key:         "DO_SHELL",
		label:       "Shell environment",
		description: "Zsh, Oh My Zsh, plugins, zshrc",
		checked:     true,
	},
	{
		key:         "DO_AI_TOOLS",
		label:       "AI Tools",
		description: "Gemini CLI",
		checked:     true,
	},
	{
		key:         "DO_DEV_TOOLS",
		label:       "Developer Tools",
		description: "bat fzf jq ripgrep lsd micro tmux starship btop go python node openjdk nushell zoxide...",
		checked:     true,
	},
	{
		key:         "DO_PKG_MGRS",
		label:       "Package Managers",
		description: "npm · yarn · pipx · uv · rustup",
		checked:     true,
	},
	{
		key:         "DO_SECURITY",
		label:       "Security Tools",
		description: "1Password CLI · nmap · openssl · yara · wtfis · ngrep · wireshark",
		checked:     true,
	},
	{
		key:         "DO_CLOUD_CLI",
		label:       "Cloud / CLI",
		description: "AWS CLI · rclone",
		checked:     true,
	},
	{
		key:         "DO_FONTS",
		label:       "Nerd Fonts",
		description: "13 Nerd Font families",
		checked:     true,
	},
	{
		key:         "DO_PROJECTOR",
		label:       "Projector Stack",
		description: "weathr · trippy · terminal animation",
		checked:     true,
	},
}

// desktopItem is shown only on macOS (--mac flag).
var desktopItem = item{
	key:         "DO_DESKTOP",
	label:       "Desktop Apps (macOS)",
	description: "iTerm2 · Keka",
	checked:     true,
}

// wslItem is shown only on Windows (--windows flag).
var wslItem = item{
	key:         "DO_WSL",
	label:       "WSL Setup",
	description: "Install WSL2 + Ubuntu (run install_linux.sh inside for full Zsh/OMZ)",
	checked:     false, // opt-in: most Windows users may not need WSL
}

// windowsShellDesc overrides the baseItems DO_SHELL description on Windows.
const windowsShellDesc = "PowerShell profile, Oh My Posh, PS modules, aliases"

// ─── Styles ──────────────────────────────────────────────────────────────────

var (
	styleBanner = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("14")). // bright cyan
			Padding(0, 1)

	styleDivider = lipgloss.NewStyle().
			Foreground(lipgloss.Color("8")). // dark gray
			Padding(0, 2)

	styleCursor = lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")). // bright red
			Bold(true)

	styleChecked = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10")). // bright green
			Bold(true)

	styleUnchecked = lipgloss.NewStyle().
			Foreground(lipgloss.Color("8")) // dark gray

	styleActiveLabel = lipgloss.NewStyle().
				Foreground(lipgloss.Color("15")). // bright white
				Bold(true)

	styleInactiveLabel = lipgloss.NewStyle().
				Foreground(lipgloss.Color("7")) // gray

	styleDescription = lipgloss.NewStyle().
				Foreground(lipgloss.Color("8")). // dim gray
				Italic(true)

	styleHelp = lipgloss.NewStyle().
			Foreground(lipgloss.Color("8")). // dark gray
			Padding(1, 1, 0, 1)

	styleScrollIndicator = lipgloss.NewStyle().
				Foreground(lipgloss.Color("8"))
)

// ─── Model ───────────────────────────────────────────────────────────────────

type model struct {
	items    []item
	cursor   int
	offset   int
	height   int
	width    int
	showMac  bool
	showWin  bool
	aborted  bool
	quitting bool
}

const (
	bannerLines  = 3
	helpLines    = 2
	reservedRows = bannerLines + helpLines
)

func (m *model) visibleRows() int {
	v := m.height - reservedRows
	if v < 1 {
		return 1
	}
	return v
}

func initialModel(showMac, showWin bool) model {
	items := make([]item, len(baseItems))
	copy(items, baseItems)

	// On Windows: override DO_SHELL description to be PS-specific.
	if showWin {
		for i := range items {
			if items[i].key == "DO_SHELL" {
				items[i].description = windowsShellDesc
			}
		}
		items = append(items, wslItem)
	}

	// On macOS: add Desktop Apps item.
	if showMac {
		items = append(items, desktopItem)
	}

	return model{
		items:   items,
		showMac: showMac,
		showWin: showWin,
		height:  24,
		width:   80,
	}
}

// ─── Init ────────────────────────────────────────────────────────────────────

func (m model) Init() tea.Cmd {
	return nil
}

// ─── Update ──────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.height = msg.Height
		m.width = msg.Width
		m.clampOffset()
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {

		case "ctrl+c", "q":
			m.aborted = true
			m.quitting = true
			return m, tea.Quit

		case "enter":
			m.quitting = true
			return m, tea.Quit

		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
				m.clampOffset()
			}

		case "down", "j":
			if m.cursor < len(m.items)-1 {
				m.cursor++
				m.clampOffset()
			}

		case " ":
			m.items[m.cursor].checked = !m.items[m.cursor].checked

		case "a":
			anyUnchecked := false
			for _, it := range m.items {
				if !it.checked {
					anyUnchecked = true
					break
				}
			}
			for i := range m.items {
				m.items[i].checked = anyUnchecked
			}
		}
	}
	return m, nil
}

func (m *model) clampOffset() {
	visible := m.visibleRows()
	if m.cursor >= m.offset+visible {
		m.offset = m.cursor - visible + 1
	}
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.offset < 0 {
		m.offset = 0
	}
}

// ─── View ────────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.quitting {
		return ""
	}

	var sb strings.Builder

	sb.WriteString(styleBanner.Render("  ⌁  terminal-kniferoll  —  select tool groups"))
	sb.WriteString("\n")
	sb.WriteString(styleDivider.Render("  " + strings.Repeat("─", 50)))
	sb.WriteString("\n")

	visible := m.visibleRows()
	end := m.offset + visible
	if end > len(m.items) {
		end = len(m.items)
	}

	for i := m.offset; i < end; i++ {
		it := m.items[i]
		active := i == m.cursor

		var cursorStr string
		if active {
			cursorStr = styleCursor.Render("❯ ")
		} else {
			cursorStr = "  "
		}

		var checkStr string
		if it.checked {
			checkStr = styleChecked.Render("[✓]")
		} else {
			checkStr = styleUnchecked.Render("[ ]")
		}

		var labelStr string
		if active {
			labelStr = styleActiveLabel.Render(it.label)
		} else {
			labelStr = styleInactiveLabel.Render(it.label)
		}

		descStr := styleDescription.Render(" — " + it.description)

		sb.WriteString(cursorStr + checkStr + " " + labelStr + descStr + "\n")
	}

	needsScroll := len(m.items) > visible
	if needsScroll {
		sb.WriteString(styleScrollIndicator.Render("  ↑↓ scroll") + "\n")
	} else {
		sb.WriteString("\n")
	}

	sb.WriteString(styleHelp.Render("SPACE toggle · ENTER confirm · a toggle all · q abort"))

	return sb.String()
}

// ─── Output ──────────────────────────────────────────────────────────────────

func printResults(items []item, aborted bool) {
	if aborted {
		for _, it := range items {
			fmt.Printf("%s=true\n", it.key)
		}
		return
	}
	for _, it := range items {
		val := "false"
		if it.checked {
			val = "true"
		}
		fmt.Printf("%s=%s\n", it.key, val)
	}
}

// ─── Main ────────────────────────────────────────────────────────────────────

func main() {
	showMac := false
	showWin := false
	for _, arg := range os.Args[1:] {
		switch arg {
		case "--mac":
			showMac = true
		case "--windows":
			showWin = true
		}
	}

	m := initialModel(showMac, showWin)

	p := tea.NewProgram(m, tea.WithAltScreen())
	finalModel, err := p.Run()
	if err != nil {
		for _, it := range m.items {
			fmt.Printf("%s=true\n", it.key)
		}
		os.Exit(1)
	}

	fm, ok := finalModel.(model)
	if !ok {
		for _, it := range m.items {
			fmt.Printf("%s=true\n", it.key)
		}
		os.Exit(1)
	}

	printResults(fm.items, fm.aborted)
}

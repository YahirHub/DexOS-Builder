package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unicode"
	"unsafe"
)

type network struct {
	SSID     string
	Signal   int
	Security string
	Active   bool
}

type termState struct {
	fd   int
	orig syscall.Termios
}

func ioctlTermios(fd int, req uintptr, value *syscall.Termios) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), req, uintptr(unsafe.Pointer(value)))
	if errno != 0 {
		return errno
	}
	return nil
}

func rawTerminal(fd int) (*termState, error) {
	var orig syscall.Termios
	if err := ioctlTermios(fd, syscall.TCGETS, &orig); err != nil {
		return nil, err
	}
	raw := orig
	raw.Lflag &^= syscall.ICANON | syscall.ECHO
	raw.Cc[syscall.VMIN] = 1
	raw.Cc[syscall.VTIME] = 0
	if err := ioctlTermios(fd, syscall.TCSETS, &raw); err != nil {
		return nil, err
	}
	return &termState{fd: fd, orig: orig}, nil
}

func (t *termState) restore() {
	if t != nil {
		_ = ioctlTermios(t.fd, syscall.TCSETS, &t.orig)
	}
}

func setEcho(fd int, enabled bool) (*syscall.Termios, error) {
	var orig syscall.Termios
	if err := ioctlTermios(fd, syscall.TCGETS, &orig); err != nil {
		return nil, err
	}
	next := orig
	if enabled {
		next.Lflag |= syscall.ECHO
	} else {
		next.Lflag &^= syscall.ECHO
	}
	if err := ioctlTermios(fd, syscall.TCSETS, &next); err != nil {
		return nil, err
	}
	return &orig, nil
}

func restoreTermios(fd int, t *syscall.Termios) {
	if t != nil {
		_ = ioctlTermios(fd, syscall.TCSETS, t)
	}
}

func splitEscaped(s string, sep byte) []string {
	var out []string
	var b strings.Builder
	escaped := false
	for i := 0; i < len(s); i++ {
		c := s[i]
		if escaped {
			b.WriteByte(c)
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if c == sep {
			out = append(out, b.String())
			b.Reset()
			continue
		}
		b.WriteByte(c)
	}
	if escaped {
		b.WriteByte('\\')
	}
	out = append(out, b.String())
	return out
}

func safeText(s string, max int) string {
	var b strings.Builder
	count := 0
	for _, r := range s {
		if count >= max {
			b.WriteRune('…')
			break
		}
		if unicode.IsControl(r) {
			b.WriteRune('?')
		} else {
			b.WriteRune(r)
		}
		count++
	}
	return b.String()
}

func nmcli(args ...string) ([]byte, error) {
	cmd := exec.Command("nmcli", args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	return out.Bytes(), err
}

func nmcliWithInput(input string, args ...string) ([]byte, error) {
	cmd := exec.Command("nmcli", args...)
	cmd.Stdin = strings.NewReader(input)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	err := cmd.Run()
	return out.Bytes(), err
}

func ensureRoot() error {
	if os.Geteuid() == 0 {
		return nil
	}
	doas, err := exec.LookPath("doas")
	if err != nil {
		return errors.New("se necesita root o doas")
	}
	argv := append([]string{"doas", os.Args[0]}, os.Args[1:]...)
	return syscall.Exec(doas, argv, os.Environ())
}

func wifiDevice() (string, error) {
	out, err := nmcli("-t", "-f", "DEVICE,TYPE,STATE", "device", "status")
	if err != nil {
		return "", fmt.Errorf("nmcli device status: %w", err)
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		fields := splitEscaped(line, ':')
		if len(fields) >= 2 && fields[1] == "wifi" && fields[0] != "" {
			return fields[0], nil
		}
	}
	return "", errors.New("no se detectó un adaptador Wi-Fi administrado por NetworkManager")
}

func wifiStatus(dev string) string {
	out, err := nmcli("-t", "-f", "GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY", "device", "show", dev)
	if err != nil {
		return "estado no disponible"
	}
	state := "desconectado"
	conn := "--"
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := splitEscaped(line, ':')
		if len(f) < 2 {
			continue
		}
		switch f[0] {
		case "GENERAL.STATE":
			state = f[1]
		case "GENERAL.CONNECTION":
			if f[1] != "" {
				conn = f[1]
			}
		}
	}
	return fmt.Sprintf("%s · %s", state, conn)
}

func scanNetworks(dev string) ([]network, error) {
	_, _ = nmcli("radio", "wifi", "on")
	_, _ = nmcli("device", "wifi", "rescan", "ifname", dev)
	time.Sleep(900 * time.Millisecond)
	out, err := nmcli("-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list", "ifname", dev)
	if err != nil {
		return nil, fmt.Errorf("no se pudo escanear: %s", strings.TrimSpace(string(out)))
	}
	best := map[string]network{}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		f := splitEscaped(line, ':')
		if len(f) < 4 || f[3] == "" {
			continue
		}
		sig, _ := strconv.Atoi(f[1])
		n := network{SSID: f[3], Signal: sig, Security: f[2], Active: f[0] == "*" || strings.EqualFold(f[0], "yes")}
		old, ok := best[n.SSID]
		if !ok || n.Signal > old.Signal || n.Active {
			best[n.SSID] = n
		}
	}
	list := make([]network, 0, len(best))
	for _, n := range best {
		list = append(list, n)
	}
	sort.Slice(list, func(i, j int) bool {
		if list[i].Active != list[j].Active {
			return list[i].Active
		}
		return list[i].Signal > list[j].Signal
	})
	return list, nil
}

func signalBars(v int) string {
	switch {
	case v >= 80:
		return "▂▄▆█"
	case v >= 60:
		return "▂▄▆_"
	case v >= 40:
		return "▂▄__"
	case v >= 20:
		return "▂___"
	default:
		return "____"
	}
}

func secured(sec string) bool {
	s := strings.ToUpper(strings.TrimSpace(sec))
	return s != "" && s != "--" && s != "NONE"
}

func enterprise(sec string) bool {
	s := strings.ToUpper(sec)
	return strings.Contains(s, "802.1X") || strings.Contains(s, "EAP") || strings.Contains(s, "ENTERPRISE")
}

func promptLine(label string) (string, error) {
	fmt.Print(label)
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	return strings.TrimSpace(line), err
}

func promptPassword(label string) (string, error) {
	fmt.Print(label)
	fd := int(os.Stdin.Fd())
	orig, err := setEcho(fd, false)
	if err != nil {
		return "", err
	}
	defer restoreTermios(fd, orig)
	reader := bufio.NewReader(os.Stdin)
	line, readErr := reader.ReadString('\n')
	fmt.Println()
	return strings.TrimRight(line, "\r\n"), readErr
}

func connectNetwork(dev string, n network, hidden bool) error {
	if enterprise(n.Security) {
		return errors.New("esta red usa autenticación Enterprise/EAP; configúrala con nmcli para indicar usuario/certificados")
	}
	args := []string{"--wait", "45", "device", "wifi", "connect", n.SSID, "ifname", dev}
	if hidden {
		args = append(args, "hidden", "yes")
	}
	var out []byte
	var err error
	if secured(n.Security) {
		password, pErr := promptPassword("Contraseña Wi-Fi: ")
		if pErr != nil {
			return pErr
		}
		if password == "" {
			return errors.New("la contraseña no puede estar vacía para esta red")
		}
		args = append([]string{"--ask"}, args...)
		out, err = nmcliWithInput(password+"\n", args...)
		password = ""
	} else {
		out, err = nmcli(args...)
	}
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return errors.New(msg)
	}
	return nil
}

func manualConnect(dev string) error {
	ssid, err := promptLine("SSID exacto: ")
	if err != nil || ssid == "" {
		return errors.New("SSID vacío")
	}
	password, err := promptPassword("Contraseña (Enter si es abierta): ")
	if err != nil {
		return err
	}
	n := network{SSID: ssid, Security: "--"}
	if password != "" {
		n.Security = "WPA"
	}
	args := []string{"--wait", "45", "device", "wifi", "connect", n.SSID, "ifname", dev, "hidden", "yes"}
	var out []byte
	if password != "" {
		args = append([]string{"--ask"}, args...)
		out, err = nmcliWithInput(password+"\n", args...)
	} else {
		out, err = nmcli(args...)
	}
	password = ""
	if err != nil {
		return errors.New(strings.TrimSpace(string(out)))
	}
	return nil
}

func clear() { fmt.Print("\x1b[2J\x1b[H") }

func draw(dev string, nets []network, selected int, message string) {
	clear()
	fmt.Println("╔══════════════════════════════════════════════════════════════════════╗")
	fmt.Println("║                         DexOS Wi-Fi TUI                             ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════════════╝")
	fmt.Printf(" Adaptador: %-18s Estado: %s\n", safeText(dev, 18), safeText(wifiStatus(dev), 44))
	fmt.Println("────────────────────────────────────────────────────────────────────────")
	if len(nets) == 0 {
		fmt.Println("  No hay redes visibles. Pulsa R para volver a escanear o M para SSID oculto.")
	} else {
		max := len(nets)
		if max > 14 {
			max = 14
		}
		start := 0
		if selected >= max {
			start = selected - max + 1
		}
		end := start + max
		if end > len(nets) {
			end = len(nets)
		}
		for i := start; i < end; i++ {
			n := nets[i]
			cursor := "  "
			if i == selected {
				cursor = "▶ "
			}
			active := " "
			if n.Active {
				active = "●"
			}
			fmt.Printf("%s%s %-32s %3d%% %-4s %-18s\n", cursor, active, safeText(n.SSID, 32), n.Signal, signalBars(n.Signal), safeText(n.Security, 18))
		}
	}
	fmt.Println("────────────────────────────────────────────────────────────────────────")
	fmt.Println(" ↑/↓ seleccionar · Enter conectar · R refrescar · M SSID oculto · Q salir")
	if message != "" {
		fmt.Printf(" %s\n", safeText(message, 68))
	}
}

func readKey() string {
	buf := make([]byte, 3)
	n, err := os.Stdin.Read(buf[:1])
	if err != nil || n == 0 {
		return "q"
	}
	if buf[0] == 0x1b {
		_, _ = os.Stdin.Read(buf[1:2])
		if buf[1] == '[' {
			_, _ = os.Stdin.Read(buf[2:3])
			switch buf[2] {
			case 'A':
				return "up"
			case 'B':
				return "down"
			}
		}
		return "esc"
	}
	if buf[0] == '\r' || buf[0] == '\n' {
		return "enter"
	}
	return strings.ToLower(string(buf[0]))
}

func tui() error {
	if err := ensureRoot(); err != nil {
		return err
	}
	dev, err := wifiDevice()
	if err != nil {
		return err
	}
	nets, scanErr := scanNetworks(dev)
	message := ""
	if scanErr != nil {
		message = scanErr.Error()
	}
	selected := 0
	fd := int(os.Stdin.Fd())
	raw, err := rawTerminal(fd)
	if err != nil {
		return errors.New("wifi TUI necesita una terminal interactiva")
	}
	defer raw.restore()
	fmt.Print("\x1b[?1049h\x1b[?25l")
	defer fmt.Print("\x1b[?25h\x1b[?1049l")

	for {
		if selected >= len(nets) && len(nets) > 0 {
			selected = len(nets) - 1
		}
		draw(dev, nets, selected, message)
		message = ""
		switch readKey() {
		case "q", "esc":
			return nil
		case "up":
			if selected > 0 {
				selected--
			}
		case "down":
			if selected+1 < len(nets) {
				selected++
			}
		case "r":
			raw.restore()
			fmt.Print("\x1b[?25h")
			nets, scanErr = scanNetworks(dev)
			if scanErr != nil {
				message = scanErr.Error()
			}
			raw, err = rawTerminal(fd)
			if err != nil {
				return err
			}
			fmt.Print("\x1b[?25l")
		case "m":
			raw.restore()
			fmt.Print("\x1b[?25h")
			clear()
			err = manualConnect(dev)
			if err != nil {
				message = "Error: " + err.Error()
			} else {
				message = "Conexión guardada y activada."
			}
			nets, _ = scanNetworks(dev)
			raw, err = rawTerminal(fd)
			if err != nil {
				return err
			}
			fmt.Print("\x1b[?25l")
		case "enter":
			if len(nets) == 0 {
				continue
			}
			n := nets[selected]
			raw.restore()
			fmt.Print("\x1b[?25h")
			clear()
			fmt.Printf("Conectando a %s...\n", safeText(n.SSID, 64))
			err = connectNetwork(dev, n, false)
			if err != nil {
				message = "Error: " + err.Error()
			} else {
				message = "Conectado a " + n.SSID
			}
			nets, _ = scanNetworks(dev)
			raw, err = rawTerminal(fd)
			if err != nil {
				return err
			}
			fmt.Print("\x1b[?25l")
		}
	}
}

func textStatus() error {
	dev, err := wifiDevice()
	if err != nil {
		return err
	}
	fmt.Printf("Adaptador: %s\nEstado: %s\n", dev, wifiStatus(dev))
	return nil
}

func textScan() error {
	dev, err := wifiDevice()
	if err != nil {
		return err
	}
	nets, err := scanNetworks(dev)
	if err != nil {
		return err
	}
	for _, n := range nets {
		fmt.Printf("%3d%%  %-34s  %s\n", n.Signal, safeText(n.SSID, 34), safeText(n.Security, 24))
	}
	return nil
}

func usage() {
	fmt.Println(`Uso: wifi [comando]

  wifi          Abrir TUI interactivo (flechas + Enter)
  wifi status   Mostrar estado Wi-Fi
  wifi scan     Listar redes visibles
  wifi help     Mostrar esta ayuda

El TUI permite refrescar, seleccionar una red, introducir la contraseña sin eco
y conectarse. Para redes ocultas pulsa M.`)
}

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "help", "-h", "--help":
			usage()
			return
		}
	}
	if _, err := exec.LookPath("nmcli"); err != nil {
		fmt.Fprintln(os.Stderr, "ERROR: NetworkManager/nmcli no está disponible.")
		os.Exit(1)
	}
	var err error
	if len(os.Args) == 1 {
		err = tui()
	} else {
		switch os.Args[1] {
		case "status":
			err = textStatus()
		case "scan":
			err = textScan()
		default:
			usage()
			os.Exit(2)
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERROR:", err)
		os.Exit(1)
	}
}

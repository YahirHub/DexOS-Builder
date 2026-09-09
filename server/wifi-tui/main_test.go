package main

import "testing"

func TestSplitEscaped(t *testing.T) {
	got := splitEscaped(`*:88:WPA2:Casa\:5G`, ':')
	want := []string{"*", "88", "WPA2", "Casa:5G"}
	if len(got) != len(want) {
		t.Fatalf("len=%d want=%d %#v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("[%d]=%q want %q", i, got[i], want[i])
		}
	}
}

func TestSafeTextRemovesControlCharacters(t *testing.T) {
	got := safeText("Casa\x1b[31m", 20)
	if got != "Casa?[31m" {
		t.Fatalf("got %q", got)
	}
}

func TestSecurityClassification(t *testing.T) {
	if secured("--") || secured("") {
		t.Fatal("red abierta detectada como protegida")
	}
	if !secured("WPA2 WPA3") {
		t.Fatal("WPA no detectado")
	}
	if !enterprise("WPA2 802.1X") {
		t.Fatal("Enterprise no detectado")
	}
}

package launcher

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestHeadlessWorkerManifestRequiresAdjacentDeclaredAssets(t *testing.T) {
	root := writeFixture(t)
	var manifest BundleManifest
	readJSON(t, filepath.Join(root, "runtime", "versions", "1.2.3", manifestFileName), &manifest)
	manifest.HeadlessWorkerPath = "headless-worker"
	if err := manifest.validate(); err == nil {
		t.Fatal("missing worker payload accepted")
	}
	for _, name := range []string{"node.exe", "worker.mjs", "node.pin.json", "LICENSE", "LICENSE-AkuSidecar"} {
		manifest.Payload = append(manifest.Payload, PayloadFile{Path: "headless-worker/" + name, Size: 1, SHA256: strings.Repeat("a", 64)})
	}
	if err := manifest.validate(); err != nil {
		t.Fatal(err)
	}
	manifest.HeadlessWorkerPath = "../headless-worker"
	if err := manifest.validate(); err == nil {
		t.Fatal("non-adjacent worker accepted")
	}
}

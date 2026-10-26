#!/usr/bin/env python3
"""Exercise session environment changes without touching the host user manager."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[2] / "system_files/usr/libexec/dux-niri-environment"
VARIABLES = ("QT_QPA_PLATFORMTHEME", "QT_QPA_PLATFORMTHEME_QT6", "XDG_MENU_PREFIX")
FAKE_TOOL = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

path = Path(os.environ["TEST_MANAGER_STATE"])
state = json.loads(path.read_text())
args = sys.argv[1:]
if Path(sys.argv[0]).name == "systemctl":
    assert args.pop(0) == "--user"
    command = args.pop(0)
    if command == "show-environment":
        if state.get("fail_snapshot"):
            sys.exit(1)
        for key, value in state["manager"].items():
            subprocess.run(["bash", "-c", 'printf "%s=%q\n" "$1" "$2"',
                            "bash", key, value], check=True)
        sys.exit(0)
    if command == "set-environment":
        for arg in args:
            key, value = arg.split("=", 1)
            state["manager"][key] = value
    else:
        assert command == "unset-environment"
        if state.pop("fail_unset_once", False):
            path.write_text(json.dumps(state))
            sys.exit(1)
        for key in args:
            state["manager"].pop(key, None)
else:
    update_systemd = args[0] == "--systemd"
    if update_systemd:
        args.pop(0)
    if state.get("dbus_unavailable"):
        sys.exit(71)
    for arg in args:
        key, value = arg.split("=", 1)
        if update_systemd:
            state["manager"][key] = value
        state["dbus"][key] = value
    if state.pop("fail_update_once", False):
        path.write_text(json.dumps(state))
        sys.exit(1)
path.write_text(json.dumps(state))
'''


class NiriEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state_path = self.root / "manager.json"
        for name in ("systemctl", "dbus-update-activation-environment"):
            tool = self.root / name
            tool.write_text(FAKE_TOOL)
            tool.chmod(0o755)
        self.env = {key: value for key, value in os.environ.items() if key not in VARIABLES}
        self.env.update(
            PATH=str(self.root) + os.pathsep + os.environ["PATH"],
            XDG_RUNTIME_DIR=str(self.root),
            TEST_MANAGER_STATE=str(self.state_path),
            QT_QPA_PLATFORMTHEME="qtengine",
            QT_QPA_PLATFORMTHEME_QT6="qtengine",
        )
        self.initialize({"UNRELATED": "keep"})

    def initialize(self, manager, **flags):
        self.state_path.write_text(json.dumps({"manager": manager, "dbus": manager, **flags}))

    def state(self):
        return json.loads(self.state_path.read_text())

    def run_helper(self, action, expected=0):
        result = subprocess.run([str(HELPER), action], env=self.env,
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, expected, result.stderr)

    def test_restore_existing_values_without_shell_expansion(self):
        marker = self.root / "must-not-exist"
        before = dict(zip(VARIABLES, [f"$(touch {marker}) ' \" \\ \n",
                                      "kde", "plasma-"]))
        before["UNRELATED"] = "keep"
        self.initialize(before)
        self.env["XDG_MENU_PREFIX"] = "plasma-"
        self.run_helper("start")
        for target in ("manager", "dbus"):
            self.assertEqual(self.state()[target][VARIABLES[0]], "qtengine")
            self.assertEqual(self.state()[target][VARIABLES[1]], "qtengine")
            self.assertEqual(self.state()[target][VARIABLES[2]], "plasma-")
        self.run_helper("stop")
        self.assertEqual(self.state(), {"manager": before, "dbus": before})
        self.assertFalse(marker.exists())

    def test_restore_absent_and_empty_values(self):
        before = {"UNRELATED": "keep", VARIABLES[0]: ""}
        self.initialize(before)
        self.run_helper("start")
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)
        self.assertEqual(self.state()["dbus"], {**before, VARIABLES[1]: "", VARIABLES[2]: ""})
        self.assertFalse((self.root / "dux-niri/environment.before").exists())

    def test_custom_theme_selection_is_propagated(self):
        self.env.update(QT_QPA_PLATFORMTHEME="qt5ct", QT_QPA_PLATFORMTHEME_QT6="qt6ct")
        self.run_helper("start")
        for target in ("manager", "dbus"):
            self.assertEqual(self.state()[target][VARIABLES[0]], "qt5ct")
            self.assertEqual(self.state()[target][VARIABLES[1]], "qt6ct")

    def test_cleanup_after_partial_start_failure(self):
        before = {VARIABLES[0]: "kde", "UNRELATED": "keep"}
        self.initialize(before, fail_update_once=True)
        self.run_helper("start", expected=1)
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)
        self.assertEqual(self.state()["dbus"][VARIABLES[0]], "kde")

    def test_snapshot_failure_leaves_environment_unchanged(self):
        self.initialize({"UNRELATED": "keep"}, fail_snapshot=True)
        before = self.state()
        self.run_helper("start", expected=1)
        self.run_helper("stop")
        self.assertEqual(self.state(), before)

    def test_stop_without_snapshot_is_harmless(self):
        before = self.state()
        self.run_helper("stop")
        self.assertEqual(self.state(), before)

    def test_start_recovers_stale_snapshot_without_losing_selected_theme(self):
        self.initialize({VARIABLES[0]: "kde"})
        self.run_helper("start")
        self.run_helper("start")
        self.assertEqual(self.state()["manager"][VARIABLES[0]], "qtengine")
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], {VARIABLES[0]: "kde"})

    def test_dbus_failure_during_stop_restores_manager_and_allows_next_login(self):
        before = {VARIABLES[0]: "kde", "UNRELATED": "keep"}
        self.initialize(before)
        self.run_helper("start")
        self.state_path.write_text(json.dumps({**self.state(), "dbus_unavailable": True}))
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)
        self.assertFalse((self.root / "dux-niri/environment.before").exists())
        state = self.state()
        del state["dbus_unavailable"]
        self.state_path.write_text(json.dumps(state))
        self.run_helper("start")
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)
        self.assertEqual(self.state()["dbus"][VARIABLES[0]], "kde")

    def test_failed_manager_cleanup_is_retried_on_next_start(self):
        before = {VARIABLES[0]: "kde"}
        self.initialize(before)
        self.run_helper("start")
        self.state_path.write_text(json.dumps({**self.state(), "fail_unset_once": True}))
        self.run_helper("stop", expected=1)
        self.assertTrue((self.root / "dux-niri/environment.before").exists())
        self.run_helper("start")
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)

    def test_new_session_snapshots_new_desktop_values(self):
        self.run_helper("start")
        self.run_helper("stop")
        before = {VARIABLES[0]: "gtk3", "UNRELATED": "keep"}
        self.initialize(before)
        self.run_helper("start")
        self.run_helper("stop")
        self.assertEqual(self.state()["manager"], before)


if __name__ == "__main__":
    unittest.main()

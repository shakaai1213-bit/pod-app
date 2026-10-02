"""Offline proof that only Console opts into the shared polling policy."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ConsolePollingSourceTests(unittest.TestCase):
    def test_ios_call_site_is_identical_to_base(self):
        path = ROOT / "Sources/Presentation/Features/DirectChat/AgentChatService.swift"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), "8724166215a705c24cd4bbbd9fc115c408c1eac65066bac8fbfae875bf18d71a")

    def test_mac_explicitly_opts_in(self):
        source = (ROOT / "MacApp/Sources/Services/OrcaRuntimeService.swift").read_text()
        self.assertIn("policy: .console,", source)

if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
import re
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cloud-assistant-deploy-usage-reconcile-worker.sh")


class UsageReconcileWorkerEnvTest(unittest.TestCase):
    def test_worker_env_uses_runtime_feishu_variable_names(self):
        source = SCRIPT.read_text()

        self.assertIn('sub("^PROD_"; "")', source)

        for name in [
            "USAGE_RECONCILE_FEISHU_APP_SECRET",
            "USAGE_RECONCILE_FEISHU_VERIFICATION_TOKEN",
        ]:
            self.assertRegex(source, rf"append_required_secret_env_as .* {name}\b")

    def test_worker_env_sets_feishu_http_endpoint_explicitly(self):
        source = SCRIPT.read_text()

        self.assertIn("USAGE_RECONCILE_FEISHU_HTTP_ADDR=0.0.0.0:3080", source)
        self.assertIn(
            "USAGE_RECONCILE_FEISHU_EVENT_PATH=/feishu/usage-reconcile/events",
            source,
        )


if __name__ == "__main__":
    unittest.main()

import { createRequire } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const Catalog = require("../contents/ui/core/MetricsCatalog.js");

// Temperature and sensor-value tests for MetricsCatalog.js.


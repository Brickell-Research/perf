#!/usr/bin/env python3
"""
Caffeine benchmark corpus generator.

Generates .caffeine measurement and expectation files at various scales
for benchmarking the caffeine compiler with hyperfine.

Corpus dimensions:
  - Measurement complexity: small, medium, large, huge
  - Expectation count: 10, 50, 100, 500, 1000
  - Type diversity: simple (String/Int/Bool), mixed, complex (nested collections, refinements)
"""

import os
import random
import string
import shutil

PERF_DIR = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(PERF_DIR, "corpus")

# --- Deterministic randomness ---
random.seed(42)

# --- Name pools ---
SERVICES = [
    "checkout", "auth", "payments", "orders", "inventory", "shipping",
    "notifications", "analytics", "search", "recommendations", "billing",
    "users", "profiles", "catalog", "cart", "gateway", "messaging",
    "scheduler", "monitoring", "logging", "cache", "storage", "cdn",
    "ml_inference", "etl_pipeline", "data_warehouse", "event_bus",
    "rate_limiter", "circuit_breaker", "load_balancer", "dns_resolver",
    "session_manager", "token_service", "audit_log", "webhook_relay",
    "media_processor", "pdf_generator", "email_sender", "sms_gateway",
    "push_notifications", "feature_flags", "ab_testing", "config_server",
    "secrets_manager", "certificate_authority", "vpn_gateway", "firewall",
    "intrusion_detection", "compliance_checker", "backup_service", "disaster_recovery",
]

ORGS = ["acme", "globex", "initech", "hooli", "piedpiper", "waystar", "delos", "massive_dynamic"]

TEAMS = [
    "platform", "payments", "growth", "infrastructure", "mobile",
    "backend", "frontend", "data", "security", "reliability",
    "devops", "sre", "ml", "search", "messaging",
    "identity", "commerce", "analytics", "observability", "networking",
]

ENVS = ["production", "staging", "development", "canary"]
VENDORS = ["datadog"]  # Primary vendor for benchmarking
METRICS = [
    "http.requests", "http.latency.p50", "http.latency.p95", "http.latency.p99",
    "http.errors", "grpc.requests", "grpc.latency", "grpc.errors",
    "db.queries", "db.latency", "db.connections", "db.errors",
    "cache.hits", "cache.misses", "cache.latency", "cache.evictions",
    "queue.messages", "queue.latency", "queue.depth", "queue.errors",
    "cpu.utilization", "memory.usage", "disk.io", "network.throughput",
]


def indent(text, level=0):
    return "  " * level + text


# --- Type generators ---

def simple_type():
    """Return a simple primitive type."""
    return random.choice(["String", "Integer", "Float", "Boolean"])


def oneof_type(base="String"):
    """Return a OneOf refinement type."""
    if base == "String":
        values = random.sample(["active", "inactive", "pending", "archived", "draft", "published"], random.randint(2, 5))
        set_str = ", ".join(f'"{v}"' for v in values)
        return f'String {{ x | x in {{ {set_str} }} }}'
    elif base == "Integer":
        values = random.sample(range(1, 100), random.randint(2, 4))
        set_str = ", ".join(str(v) for v in sorted(values))
        return f'Integer {{ x | x in {{ {set_str} }} }}'
    return simple_type()


def range_type():
    """Return an InclusiveRange refinement type."""
    if random.random() < 0.5:
        low = round(random.uniform(0, 50), 1)
        high = round(random.uniform(60, 100), 1)
        return f"Float {{ x | x in ( {low}..{high} ) }}"
    else:
        low = random.randint(0, 50)
        high = random.randint(60, 1000)
        return f"Integer {{ x | x in ( {low}..{high} ) }}"


def collection_type(depth=0):
    """Return a collection type (List or Dict)."""
    if depth > 1:
        return simple_type()
    if random.random() < 0.6:
        inner = random_type(depth + 1, allow_complex=False)
        return f"List({inner})"
    else:
        val_type = random_type(depth + 1, allow_complex=False)
        return f"Dict(String, {val_type})"


def modifier_type(depth=0):
    """Return a modifier type (Optional or Defaulted)."""
    inner = random_type(depth + 1, allow_complex=False)
    if random.random() < 0.5:
        return f"Optional({inner})"
    else:
        # Defaulted needs a default value matching the inner type
        if inner == "String":
            return f'Defaulted(String, "default")'
        elif inner == "Integer":
            return f"Defaulted(Integer, 0)"
        elif inner == "Float":
            return f"Defaulted(Float, 0.0)"
        elif inner == "Boolean":
            return f"Defaulted(Boolean, false)"
        else:
            return f"Optional({inner})"


def random_type(depth=0, allow_complex=True):
    """Return a random type of varying complexity."""
    if depth > 2 or not allow_complex:
        return simple_type()

    r = random.random()
    if r < 0.40:
        return simple_type()
    elif r < 0.55:
        return oneof_type(random.choice(["String", "Integer"]))
    elif r < 0.65:
        return range_type()
    elif r < 0.80:
        return collection_type(depth)
    else:
        return modifier_type(depth)


_alias_registry = {}  # Filled during alias generation, maps alias name -> underlying type


def value_for_type(type_str):
    """Generate a valid literal value for a given type string."""
    t = type_str.strip()

    # Resolve type aliases
    if t.startswith("_") and t in _alias_registry:
        return value_for_type(_alias_registry[t])

    if t == "String":
        return f'"{"".join(random.choices(string.ascii_lowercase, k=random.randint(5, 15)))}"'
    elif t == "Integer":
        return str(random.randint(1, 10000))
    elif t == "Float":
        return str(round(random.uniform(0.01, 100.0), 2))
    elif t == "Boolean":
        return random.choice(["true", "false"])
    elif t == "URL":
        return f'"https://example.com/{"".join(random.choices(string.ascii_lowercase, k=8))}"'
    elif t == "Percentage":
        return f"{round(random.uniform(0.0, 100.0), 2)}%"
    elif t.startswith("String { x | x in {"):
        # OneOf String - extract values and pick one
        inner = t.split("{")[-1].rstrip(" }")
        vals = [v.strip().strip('"') for v in inner.split(",")]
        return f'"{random.choice(vals)}"'
    elif t.startswith("Integer { x | x in {"):
        inner = t.split("{")[-1].rstrip(" }")
        vals = [v.strip() for v in inner.split(",")]
        return random.choice(vals)
    elif "x | x in (" in t and ".." in t:
        # InclusiveRange - pick a value in range
        # Extract the range part between ( and )
        import re
        match = re.search(r'\(\s*([\d.]+)\s*\.\.\s*([\d.]+)\s*\)', t)
        if not match:
            return "50"
        low = float(match.group(1))
        high = float(match.group(2))
        if "Float" in t:
            return str(round(random.uniform(low, high), 2))
        else:
            return str(random.randint(int(low), int(high)))
    elif t.startswith("List("):
        inner = t[5:-1]
        count = random.randint(1, 4)
        vals = [value_for_type(inner) for _ in range(count)]
        return "[" + ", ".join(vals) + "]"
    elif t.startswith("Dict(String, "):
        val_type = t[13:-1]
        count = random.randint(1, 3)
        pairs = []
        for i in range(count):
            key = f"key_{i}"
            val = value_for_type(val_type)
            pairs.append(f'{key}: {val}')
        return "{ " + ", ".join(pairs) + " }"
    elif t.startswith("Optional("):
        inner = t[9:-1]
        # Optional fields: always provide a value (omitting is also valid but simpler to provide)
        return value_for_type(inner)
    elif t.startswith("Defaulted("):
        # Defaulted(Type, default) - can omit or provide
        parts = t[10:-1].split(", ", 1)
        inner = parts[0]
        return value_for_type(inner)
    else:
        return f'"fallback_value"'


# --- Blueprint generators ---

def gen_type_aliases(count):
    """Generate type alias definitions."""
    _alias_registry.clear()
    aliases = []
    alias_names = []
    for i in range(count):
        name = f"_type_{i}"
        alias_names.append(name)
        if random.random() < 0.5:
            values = random.sample(ENVS + ["qa", "test", "demo", "perf"], random.randint(2, 5))
            set_str = ", ".join(f'"{v}"' for v in values)
            underlying = f'String {{ x | x in {{ {set_str} }} }}'
            aliases.append(f'{name} (Type): {underlying}')
            _alias_registry[name] = underlying
        else:
            low = round(random.uniform(0, 50), 1)
            high = round(random.uniform(60, 100), 1)
            underlying = f'Float {{ x | x in ( {low}..{high} ) }}'
            aliases.append(f'{name} (Type): {underlying}')
            _alias_registry[name] = underlying
    return aliases, alias_names


def gen_extendables(req_count, prov_count):
    """Generate extendable definitions."""
    extendables = []
    req_names = []
    prov_names = []

    for i in range(req_count):
        name = f"_req_{i}"
        req_names.append(name)
        fields = []
        num_fields = random.randint(1, 3)
        for j in range(num_fields):
            fname = f"req_{i}_field_{j}"
            ftype = simple_type()
            fields.append(f"{fname}: {ftype}")
        extendables.append(f'{name} (Requires): {{ {", ".join(fields)} }}')

    # Provides extendables share common evaluation patterns.
    # Vendor is now determined by the measurement filename, not a field.
    for i in range(prov_count):
        name = f"_prov_{i}"
        prov_names.append(name)
        extendables.append(f'{name} (Provides): {{ evaluation: "numerator / denominator" }}')

    return extendables, req_names, prov_names


def gen_measurement_item(name, req_ext_names, prov_ext_names, alias_names, complexity="medium"):
    """Generate a single measurement item (top-level, no header/bullet)."""
    lines = []

    # Extends clause
    extends = []
    if prov_ext_names and random.random() < 0.6:
        extends.extend(random.sample(prov_ext_names, min(random.randint(1, 2), len(prov_ext_names))))
    if req_ext_names and random.random() < 0.5:
        extends.extend(random.sample(req_ext_names, min(random.randint(1, 1), len(req_ext_names))))

    extends_str = f" extends [{', '.join(extends)}]" if extends else ""
    lines.append(f'"{name}"{extends_str}:')

    # Requires block
    req_fields = []
    if complexity == "small":
        num_req = random.randint(1, 2)
    elif complexity == "medium":
        num_req = random.randint(2, 5)
    elif complexity == "large":
        num_req = random.randint(4, 8)
    else:  # huge
        num_req = random.randint(6, 12)

    req_field_info = []  # Track (name, type) for expectation generation
    # First two fields are always plain Strings (for template variable compatibility)
    for i in range(num_req):
        fname = f"{name}_param_{i}"
        if i < 2:
            # Ensure first two fields are plain String for template vars
            ftype = "String"
        elif alias_names and random.random() < 0.2:
            ftype = random.choice(alias_names)
        elif complexity in ("large", "huge"):
            ftype = random_type(depth=0, allow_complex=True)
        else:
            ftype = random_type(depth=0, allow_complex=(complexity != "small"))
        req_fields.append(f"{fname}: {ftype}")
        req_field_info.append((fname, ftype))

    if len(req_fields) <= 2:
        lines.append(f'  Requires {{ {", ".join(req_fields)} }}')
    else:
        lines.append("  Requires {")
        for j, f in enumerate(req_fields):
            if j < len(req_fields) - 1:
                lines.append(f"    {f},")
            else:
                lines.append(f"    {f}")
        lines.append("  }")

    # Provides block - evaluation + indicators for SLO
    # Vendor is determined by the filename (e.g., datadog.caffeine), not a field.
    # If we extend a Provides extendable, evaluation is already inherited.
    has_prov_extends = any(e in extends for e in prov_ext_names) if prov_ext_names else False
    metric = random.choice(METRICS)
    env_param = None
    svc_param = None
    # Only use simple String-typed fields for template variables
    # (Dict, List, Optional etc. are not supported as template vars)
    for fname, ftype in req_field_info:
        ftype_str = str(ftype).strip()
        is_simple_string = (ftype_str == "String" or
                            ftype_str.startswith("String {") or
                            (ftype_str.startswith("_") and ftype_str in _alias_registry and
                             _alias_registry[ftype_str].startswith("String")))
        if is_simple_string and env_param is None:
            env_param = fname
        elif is_simple_string and svc_param is None:
            svc_param = fname

    # Build indicator query with template vars
    template_parts = [f"sum:{metric}{{"]
    if env_param:
        template_parts.append(f"${env_param}->{env_param}$")
    if svc_param:
        if env_param:
            template_parts.append(f",${svc_param}->{svc_param}$")
        else:
            template_parts.append(f"${svc_param}->{svc_param}$")
    template_parts.append("}")
    numerator_query = "".join(template_parts)
    denominator_query = f'sum:{metric}.total{{{f"${env_param}->{env_param}$" if env_param else ""}}}'

    lines.append("  Provides {")
    if not has_prov_extends:
        lines.append('    evaluation: "numerator / denominator",')
    lines.append("    indicators: {")
    lines.append(f'      numerator: "{numerator_query}",')
    lines.append(f'      denominator: "{denominator_query}"')
    lines.append("    }")
    lines.append("  }")

    return "\n".join(lines), req_field_info


def gen_measurements_file(num_measurements, complexity="medium", num_aliases=0, num_req_ext=0, num_prov_ext=0):
    """Generate a complete measurements .caffeine file (vendor determined by filename)."""
    sections = []

    # Type aliases
    aliases, alias_names = gen_type_aliases(num_aliases)
    if aliases:
        sections.append("\n".join(aliases))

    # Extendables
    extendables, req_ext_names, prov_ext_names = gen_extendables(num_req_ext, num_prov_ext)
    req_ext_fields = {}  # Track fields from each Requires extendable
    if extendables:
        sections.append("\n".join(extendables))
    # Parse extendable fields for tracking what expectations need to provide
    for i in range(num_req_ext):
        name = f"_req_{i}"
        fields = []
        num_fields = random.randint(1, 3)
        # Re-seed to match the extendable generation (already generated above, but we need the field info)
        # Instead, parse from the generated text
        ext_text = [e for e in extendables if e.startswith(f"{name} ")]
        if ext_text:
            import re
            field_matches = re.findall(r'(\w+): (\w+)', ext_text[0].split("{", 1)[1])
            req_ext_fields[name] = [(m[0], m[1]) for m in field_matches]

    # Measurement items (top-level, no header, blank line between items)
    measurement_names = []
    measurement_fields = {}  # name -> [(field_name, field_type)] - ALL required fields including from extends

    item_lines = []
    for i in range(num_measurements):
        service = SERVICES[i % len(SERVICES)]
        suffix = f"_{i // len(SERVICES)}" if i >= len(SERVICES) else ""
        m_name = f"{service}_slo{suffix}"
        measurement_names.append(m_name)

        item_str, field_info = gen_measurement_item(
            m_name, req_ext_names, prov_ext_names, alias_names, complexity
        )
        item_lines.append(item_str)

        # Include fields from extended Requires extendables
        all_fields = list(field_info)
        # Check which req extendables this measurement extends
        for ext_name in req_ext_names:
            if f"extends [" in item_str and ext_name in item_str:
                if ext_name in req_ext_fields:
                    all_fields.extend(req_ext_fields[ext_name])
        measurement_fields[m_name] = all_fields

    sections.append("\n\n".join(item_lines))

    content = "\n\n".join(sections) + "\n"
    return content, measurement_names, measurement_fields


def gen_expectation_file(measurement_name, fields, num_expectations, org, team):
    """Generate an expectations .caffeine file."""
    lines = [f'Expectations measured by "{measurement_name}"']

    for i in range(num_expectations):
        exp_name = f"{team}_{measurement_name}_{i}"
        lines.append(f'  * "{exp_name}":')
        lines.append("    Provides {")

        # Provide values for each required field
        for fname, ftype in fields:
            val = value_for_type(ftype)
            lines.append(f"      {fname}: {val},")

        # Standard SLO fields
        threshold = round(random.uniform(95.0, 99.99), 2)
        window = random.choice([7, 30, 90])
        lines.append(f"      threshold: {threshold}%,")
        lines.append(f"      window_in_days: {window}")
        lines.append("    }")
        # Blank line between items (formatter style)
        lines.append("")

    return "\n".join(lines)


# --- Corpus scale definitions ---

SCALES = {
    "small": {
        "num_measurements": 2,
        "complexity": "small",
        "num_aliases": 0,
        "num_req_ext": 0,
        "num_prov_ext": 0,
        "num_orgs": 1,
        "teams_per_org": 1,
        "expectations_per_team_measurement": 2,
    },
    "medium": {
        "num_measurements": 5,
        "complexity": "medium",
        "num_aliases": 2,
        "num_req_ext": 1,
        "num_prov_ext": 1,
        "num_orgs": 2,
        "teams_per_org": 2,
        "expectations_per_team_measurement": 3,
    },
    "large": {
        "num_measurements": 20,
        "complexity": "large",
        "num_aliases": 5,
        "num_req_ext": 3,
        "num_prov_ext": 3,
        "num_orgs": 3,
        "teams_per_org": 4,
        "expectations_per_team_measurement": 5,
    },
    "huge": {
        "num_measurements": 50,
        "complexity": "huge",
        "num_aliases": 10,
        "num_req_ext": 5,
        "num_prov_ext": 5,
        "num_orgs": 5,
        "teams_per_org": 5,
        "expectations_per_team_measurement": 8,
    },
    "insane": {
        "num_measurements": 50,
        "complexity": "huge",
        "num_aliases": 10,
        "num_req_ext": 5,
        "num_prov_ext": 5,
        "num_orgs": 8,
        "teams_per_org": 10,
        "expectations_per_team_measurement": 15,
    },
    "absurd": {
        "num_measurements": 50,
        "complexity": "huge",
        "num_aliases": 10,
        "num_req_ext": 5,
        "num_prov_ext": 5,
        "num_orgs": 8,
        "teams_per_org": 20,
        "expectations_per_team_measurement": 25,
    },
}

# Additional expectation-only scaling (uses the "large" blueprint)
EXPECTATION_SCALES = [10, 50, 100, 500, 1000, 2500, 5000]


def generate_scale(scale_name, config):
    """Generate a complete corpus at a given scale."""
    scale_dir = os.path.join(CORPUS_DIR, scale_name)
    if os.path.exists(scale_dir):
        shutil.rmtree(scale_dir)
    os.makedirs(scale_dir)

    # Generate measurement file (vendor is determined by filename)
    m_content, m_names, m_fields = gen_measurements_file(
        num_measurements=config["num_measurements"],
        complexity=config["complexity"],
        num_aliases=config["num_aliases"],
        num_req_ext=config["num_req_ext"],
        num_prov_ext=config["num_prov_ext"],
    )

    measurements_dir = os.path.join(scale_dir, "measurements")
    os.makedirs(measurements_dir)
    m_file = os.path.join(measurements_dir, "datadog.caffeine")
    with open(m_file, "w") as f:
        f.write(m_content)

    # Generate expectations directory structure
    exp_dir = os.path.join(scale_dir, "expectations")
    os.makedirs(exp_dir)

    num_orgs = config["num_orgs"]
    teams_per_org = config["teams_per_org"]
    exp_per = config["expectations_per_team_measurement"]
    total_expectations = 0

    for org_i in range(num_orgs):
        org_name = ORGS[org_i % len(ORGS)]
        for team_i in range(teams_per_org):
            team_name = TEAMS[team_i % len(TEAMS)]
            team_dir = os.path.join(exp_dir, org_name, team_name)
            os.makedirs(team_dir, exist_ok=True)

            # Each team file covers a subset of measurements
            ms_for_team = m_names[:max(1, len(m_names) // (num_orgs * teams_per_org) + 1)]
            # Rotate which measurements each team uses
            offset = (org_i * teams_per_org + team_i) * len(ms_for_team)
            ms_for_team = [m_names[j % len(m_names)] for j in range(offset, offset + len(ms_for_team))]
            # Deduplicate
            ms_for_team = list(dict.fromkeys(ms_for_team))

            file_content_parts = []
            for m_name in ms_for_team:
                fields = m_fields[m_name]
                part = gen_expectation_file(m_name, fields, exp_per, org_name, team_name)
                file_content_parts.append(part)
                total_expectations += exp_per

            exp_file = os.path.join(team_dir, "slos.caffeine")
            with open(exp_file, "w") as f:
                f.write("\n".join(file_content_parts))

    # Stats
    m_size = os.path.getsize(m_file)
    total_exp_size = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, fns in os.walk(exp_dir)
        for f in fns
    )
    num_exp_files = sum(1 for _, _, fns in os.walk(exp_dir) for _ in fns)

    return {
        "scale": scale_name,
        "measurements": config["num_measurements"],
        "measurement_file_size": m_size,
        "expectations_total": total_expectations,
        "expectation_files": num_exp_files,
        "expectations_dir_size": total_exp_size,
        "total_size": m_size + total_exp_size,
    }


def generate_expectation_scaling():
    """Generate corpora that vary only in expectation count, using a fixed 'large' measurement set."""
    # Generate the fixed measurement set
    config = SCALES["large"]
    m_content, m_names, m_fields = gen_measurements_file(
        num_measurements=config["num_measurements"],
        complexity=config["complexity"],
        num_aliases=config["num_aliases"],
        num_req_ext=config["num_req_ext"],
        num_prov_ext=config["num_prov_ext"],
    )

    results = []
    for target_count in EXPECTATION_SCALES:
        scale_dir = os.path.join(CORPUS_DIR, f"exp_scale_{target_count}")
        if os.path.exists(scale_dir):
            shutil.rmtree(scale_dir)
        os.makedirs(scale_dir)

        # Write measurements (vendor determined by filename)
        measurements_dir = os.path.join(scale_dir, "measurements")
        os.makedirs(measurements_dir)
        m_file = os.path.join(measurements_dir, "datadog.caffeine")
        with open(m_file, "w") as f:
            f.write(m_content)

        # Generate expectations to hit target count
        exp_dir = os.path.join(scale_dir, "expectations")
        os.makedirs(exp_dir)

        total = 0
        org_i = 0
        team_i = 0

        while total < target_count:
            org_name = ORGS[org_i % len(ORGS)]
            team_name = TEAMS[team_i % len(TEAMS)]
            team_dir = os.path.join(exp_dir, org_name, team_name)
            os.makedirs(team_dir, exist_ok=True)

            # Pick random measurements for this team
            num_ms = min(random.randint(1, 5), len(m_names))
            chosen_ms = random.sample(m_names, num_ms)

            file_parts = []
            for m_name in chosen_ms:
                remaining = target_count - total
                if remaining <= 0:
                    break
                exp_count = min(random.randint(1, 5), remaining)
                fields = m_fields[m_name]
                part = gen_expectation_file(
                    m_name, fields, exp_count,
                    org_name, f"{team_name}_{org_i}_{team_i}"
                )
                file_parts.append(part)
                total += exp_count

            if file_parts:
                exp_file = os.path.join(team_dir, "slos.caffeine")
                # Append if file exists (multiple rounds may hit same team)
                mode = "a" if os.path.exists(exp_file) else "w"
                with open(exp_file, mode) as f:
                    f.write("\n".join(file_parts))

            team_i += 1
            if team_i >= len(TEAMS):
                team_i = 0
                org_i += 1

        m_size = os.path.getsize(m_file)
        total_exp_size = sum(
            os.path.getsize(os.path.join(dp, f))
            for dp, _, fns in os.walk(exp_dir)
            for f in fns
        )
        num_exp_files = sum(1 for _, _, fns in os.walk(exp_dir) for _ in fns)

        results.append({
            "target": target_count,
            "actual_expectations": total,
            "expectation_files": num_exp_files,
            "measurement_size": m_size,
            "expectations_size": total_exp_size,
            "total_size": m_size + total_exp_size,
        })

    return results


def main():
    global _alias_registry
    if os.path.exists(CORPUS_DIR):
        shutil.rmtree(CORPUS_DIR)
    os.makedirs(CORPUS_DIR)

    print("=== Generating Caffeine Benchmark Corpus ===\n")

    # Generate complexity-scaled corpora
    print("--- Complexity Scaling ---")
    for scale_name, config in SCALES.items():
        stats = generate_scale(scale_name, config)
        print(f"  {scale_name:8s}: {stats['measurements']:3d} measurements, "
              f"{stats['expectations_total']:5d} expectations across {stats['expectation_files']:3d} files, "
              f"total {stats['total_size']:,d} bytes")

    # Generate expectation-count-scaled corpora
    print("\n--- Expectation Count Scaling (fixed 'large' measurements) ---")
    exp_results = generate_expectation_scaling()
    for r in exp_results:
        print(f"  target {r['target']:5d}: actual {r['actual_expectations']:5d} expectations, "
              f"{r['expectation_files']:3d} files, total {r['total_size']:,d} bytes")

    print(f"\nCorpus generated in: {CORPUS_DIR}")
    print("Done!")


if __name__ == "__main__":
    main()

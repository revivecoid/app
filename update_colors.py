import json
import re

tailwind_config_str = """
{
            "surface-tint": "#ffb3ad",
            "border-dark-subtle": "rgba(255, 255, 255, 0.08)",
            "primary-container": "#d10721",
            "surface-container-high": "#2b2a2b",
            "border-light-subtle": "rgba(0, 0, 0, 0.08)",
            "inverse-primary": "#c0001c",
            "on-tertiary-container": "#d8e9ff",
            "tertiary-fixed": "#cfe5ff",
            "background": "#141314",
            "inverse-surface": "#e6e1e2",
            "status-success": "#16A34A",
            "surface-variant": "#363435",
            "error-container": "#93000a",
            "secondary-fixed-dim": "#c9c5ca",
            "on-secondary-container": "#bbb7bc",
            "surface": "#141314",
            "surface-dark": "#18191C",
            "secondary-fixed": "#e6e1e6",
            "on-primary-fixed-variant": "#930013",
            "on-tertiary": "#003355",
            "on-surface": "#ffffff",
            "on-secondary": "#313033",
            "surface-container-highest": "#363435",
            "secondary": "#c9c5ca",
            "workspace-light": "#F8F9FA",
            "accent-warning": "#F59E0B",
            "tertiary": "#9acbff",
            "secondary-container": "#4a484c",
            "primary-fixed": "#ffdad7",
            "outline": "#38373a",
            "outline-variant": "#2e2d2f",
            "inverse-on-surface": "#313031",
            "on-secondary-fixed": "#1c1b1e",
            "on-tertiary-fixed-variant": "#004a78",
            "tint-damage-fill": "rgba(209, 7, 33, 0.28)",
            "tertiary-container": "#006cad",
            "on-secondary-fixed-variant": "#48464a",
            "on-surface-variant": "#9e9c9f",
            "on-error-container": "#ffdad6",
            "on-primary-container": "#ffe1de",
            "on-primary-fixed": "#410004",
            "on-primary": "#ffffff",
            "tertiary-fixed-dim": "#9acbff",
            "primary-fixed-dim": "#ffb3ad",
            "surface-container": "#201f20",
            "primary": "#ffb3ad",
            "brand-red": "#d10721",
            "surface-bright": "#3a393a",
            "on-tertiary-fixed": "#001d34",
            "on-background": "#ffffff",
            "surface-dark-elevated": "#242325",
            "surface-container-lowest": "#0f0e0f",
            "surface-dim": "#141314",
            "surface-container-low": "#1c1b1c",
            "pure-white": "#FFFFFF",
            "error": "#ffb4ab",
            "on-error": "#690005"
}
"""

colors = json.loads(tailwind_config_str)

def to_camel(s):
    parts = s.split('-')
    return parts[0] + ''.join(p.title() for p in parts[1:])

def to_flutter_color(val):
    if val.startswith('#'):
        val = val[1:]
        if len(val) == 6:
            return "Color(0xFF{})".format(val.upper())
        elif len(val) == 8:
            return "Color(0x{}{})".format(val[6:8].upper(), val[0:6].upper())
    elif val.startswith('rgba'):
        match = re.match(r'rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)', val)
        if match:
            r, g, b, a = match.groups()
            a_hex = "{:02X}".format(int(float(a) * 255))
            r_hex = "{:02X}".format(int(r))
            g_hex = "{:02X}".format(int(g))
            b_hex = "{:02X}".format(int(b))
            return "Color(0x{}{}{}{})".format(a_hex, r_hex, g_hex, b_hex)
    return "Color(0xFF000000)"

output = "class AppColors {\n"
output += "  // Brand Colors from Design Guidelines\n"
output += "  static const Color fireRed = Color(0xFFD10721);\n"
output += "  static const Color daysGray = Color(0xFF474549);\n"
output += "  static const Color sleekBlack = Color(0xFF1D1C1D);\n"
output += "  static const Color pureWhite = Color(0xFFFFFFFF);\n"
output += "  static const Color workspaceLight = Color(0xFFF8F9FA);\n\n"
output += "  // New Stitch Design System Colors\n"

for k, v in colors.items():
    camel_k = to_camel(k)
    flutter_color = to_flutter_color(v)
    output += "  static const Color {} = {};\n".format(camel_k, flutter_color)

output += "\n  // Fallbacks for backward compatibility\n"
output += "  static const Color textPrimary = Colors.white;\n"
output += "  static const Color textSecondary = Color(0xFFB3B3B3);\n"
output += "}\n"

with open("colors_out.txt", "w") as f:
    f.write(output)

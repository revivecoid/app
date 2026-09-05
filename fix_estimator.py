import re

with open("lib/features/customer_app/estimator/presentation/estimator_screen.dart", "r") as f:
    content = f.read()

# Add isDark to all _build methods
methods = [
    "_buildProgressSteps", "_buildStepLabel", "_buildInstructionBanner", "_buildPhotoUpload",
    "_buildDigitalTwin", "_buildDamageAssessmentReport", "_buildStep2", "_buildStep3",
    "_buildStep4", "_buildReviewSection", "_buildContent", "build"
]

for m in methods:
    if m == "build":
        pattern = r'(Widget build\([^)]*\)\s*{)'
    else:
        pattern = r'(Widget ' + m + r'\([^)]*\)\s*{)'
    content = re.sub(pattern, r'\1\n    final isDark = Theme.of(context).brightness == Brightness.dark;', content)

# Use regex with word boundaries or negative lookahead
replacements = {
    r'AppColors\.surfaceContainerLowest\b': r'(isDark ? AppColors.surfaceContainerLowest : Colors.white)',
    r'AppColors\.surfaceContainerHighest\b': r'(isDark ? AppColors.surfaceContainerHighest : Colors.grey.shade200)',
    r'AppColors\.surfaceContainerLow\b': r'(isDark ? AppColors.surfaceContainerLow : Colors.grey.shade50)',
    r'AppColors\.surfaceContainer\b': r'(isDark ? AppColors.surfaceContainer : Colors.grey.shade100)',
    r'AppColors\.surface\b': r'(isDark ? AppColors.surface : Colors.white)',
    r'AppColors\.onSurfaceVariant\b': r'(isDark ? AppColors.onSurfaceVariant : Colors.black54)',
    r'AppColors\.onSurface\b': r'(isDark ? AppColors.onSurface : Colors.black87)',
}

for k, v in replacements.items():
    content = re.sub(k, v, content)

with open("lib/features/customer_app/estimator/presentation/estimator_screen.dart", "w") as f:
    f.write(content)

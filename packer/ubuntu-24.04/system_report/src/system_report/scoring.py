from dataclasses import dataclass
from typing import List

@dataclass
class CheckResult:
    name: str
    passed: bool
    severity: str
    cis_level: int
    message: str

class Scorer:
    def __init__(self, cis_mode=1):
        self.cis_mode = cis_mode
        self.results: List[CheckResult] = []

    def add(self, name: str, passed: bool, severity='medium', cis_level=1, message=''):
        self.results.append(CheckResult(name, passed, severity, cis_level, message))

    def compute(self):
        weights = {'high':3, 'medium':2, 'low':1}
        total = 0
        passed = 0
        failed_list = []
        for r in self.results:
            if self.cis_mode == 1 and r.cis_level == 2:
                continue
            w = weights.get(r.severity,1)
            total += w
            if r.passed:
                passed += w
            else:
                failed_list.append({'name': r.name, 'severity': r.severity, 'message': r.message})
        score = (passed/total*100) if total>0 else 0.0
        return {'score': round(score,2), 'total_weight': total, 'passed_weight': passed, 'failed': failed_list}

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('retention', Path(__file__).resolve().parents[1] / 'scripts/retention-review.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def arn(revision):
    return f'arn:aws:ecs:eu-north-1:123456789012:task-definition/app:{revision}'


def snapshot():
    return {'definitions': [{'arn': arn(i), 'status': 'ACTIVE'} for i in range(1, 8)],
            'service_revisions': [arn(2), arn(3)], 'task_revisions': [arn(1)],
            'rollback_revisions': [arn(4)]}


class RetentionReviewTests(unittest.TestCase):
    def test_protects_active_deployments_tasks_rollback_and_recent(self):
        result = module.review(snapshot(), 2)
        self.assertEqual(result['revisions_for_manual_review'], [arn(5)])
        self.assertEqual(result['image_deletion_candidates'], [])

    def test_missing_or_inactive_references_fail_closed(self):
        for ref in (arn(100), arn(1)):
            data = snapshot()
            data['definitions'][0]['status'] = 'INACTIVE'
            data['rollback_revisions'] = [ref]
            with self.assertRaises(ValueError):
                module.review(data, 2)

    def test_rollback_must_be_explicit(self):
        data = snapshot()
        data['rollback_revisions'] = []
        with self.assertRaises(ValueError):
            module.review(data, 2)

    def test_duplicate_and_invalid_keep_fail(self):
        data = snapshot()
        data['definitions'].append(data['definitions'][0])
        with self.assertRaises(ValueError):
            module.review(data, 2)
        with self.assertRaises(ValueError):
            module.review(snapshot(), 0)


if __name__ == '__main__':
    unittest.main()

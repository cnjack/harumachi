"""Offline tests for irreversible paid-call boundaries; never contact Hyper3D."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import hyper3d_budget_batch as jobs


class PaidCallGuard(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='hyper3d-budget-test-')
        root=Path(self.temp.name)
        self.original=(jobs.ROOT,jobs.RAW,jobs.EVIDENCE)
        jobs.ROOT=root;jobs.RAW=root/'raw';jobs.EVIDENCE=root/'evidence'
        reference=root/'ref.png';reference.write_bytes(b'reference fixture')
        self.row=dict(id='fixture',reference='ref.png',model_prompt='clean anime fixture',
                      model_style='clean anime ',tier='Gen-2.5-High',mesh_mode='Quad',quality=18000)
        self.initial=dict(total=210)
        self.before=dict(total=210,available=210,frozen=0)
        self.after=dict(total=210,available=209.5,frozen=.5)
        jobs.write(jobs.EVIDENCE/'reference-reviews/fixture.json',dict(status='pass',sha256=jobs.sha(reference)))

    def tearDown(self):
        jobs.ROOT,jobs.RAW,jobs.EVIDENCE=self.original
        self.temp.cleanup()

    def reject_without_paid_call(self,message,before=None,candidate='a'):
        with patch.object(jobs,'baseline',return_value=(self.initial,before or self.before)),patch.object(jobs,'cli') as cli:
            with self.assertRaisesRegex(RuntimeError,message):jobs.submit(self.row,candidate,self.initial)
            cli.assert_not_called()

    def test_floor_uses_frozen_funds(self):
        self.reject_without_paid_call('150-point floor',dict(total=150.5,available=150,frozen=.5))

    def test_existing_slot_never_submits_twice(self):
        jobs.write(jobs.RAW/'fixture/a/intent.json',{})
        self.reject_without_paid_call('slot already used')

    def test_unknown_outcome_blocks_other_slots(self):
        jobs.write(jobs.RAW/'other/a/intent.json',{})
        self.reject_without_paid_call('ambiguous outcome')

    def test_external_spending_blocks_submission(self):
        self.reject_without_paid_call('do not match',dict(total=209,available=209,frozen=0))

    def test_reference_change_invalidates_approval(self):
        (jobs.ROOT/'ref.png').write_bytes(b'changed fixture')
        self.reject_without_paid_call('approval does not match')

    def test_second_candidate_requires_actual_feedback(self):
        self.reject_without_paid_call('write specific feedback',candidate='b')

    def test_oversize_prompt_rejected_before_intent(self):
        self.row['model_prompt']='x'*1025
        self.reject_without_paid_call('1024 character')
        self.assertFalse((jobs.RAW/'fixture/a/intent.json').exists())

    def test_timeout_locks_intent_and_does_not_retry(self):
        with patch.object(jobs,'baseline',return_value=(self.initial,self.before)),patch.object(jobs,'cli',side_effect=TimeoutError('unknown outcome')) as cli:
            with self.assertRaises(TimeoutError):jobs.submit(self.row,'a',self.initial)
            self.assertEqual(cli.call_count,1)
        self.assertTrue((jobs.RAW/'fixture/a/intent.json').is_file())
        self.reject_without_paid_call('slot already used')

    def test_frozen_half_credit_matches_one_paid_call(self):
        with patch.object(jobs,'baseline',side_effect=[(self.initial,self.before),(self.initial,self.after)]),patch.object(jobs,'cli',return_value=dict(generation_id='owned-task',status='queued')) as cli:
            jobs.submit(self.row,'a',self.initial)
            self.assertEqual(cli.call_count,1)
        charge=json.loads((jobs.RAW/'fixture/a/charge.json').read_text())
        self.assertEqual(charge['actual_committed_delta'],.5)
        self.assertEqual(charge['settled_delta'],0)


if __name__=='__main__':unittest.main()

"""Offline paid-boundary checks; mocked CLI never contacts the provider."""
import json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import hyper3d_furniture_batch_20261015 as jobs

class FurniturePaidGuard(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='furniture-paid-guard-');root=Path(self.tmp.name)
  self.old=(jobs.ROOT,jobs.RAW,jobs.EVIDENCE);jobs.ROOT=root;jobs.RAW=root/'raw';jobs.EVIDENCE=root/'evidence'
  (root/'ref.png').write_bytes(b'offline-reference')
  self.row=dict(id='fixture',reference='ref.png',model_prompt='One curved wooden chair.',tier='Gen-2.5-High',mesh_mode='Quad',quality=18000)
  self.initial=dict(total=150);self.before=dict(total=150,available=150,frozen=0);self.after=dict(total=150,available=149.5,frozen=.5)
  jobs.shared.write(jobs.EVIDENCE/'reference-reviews/fixture.json',dict(status='pass',sha256=jobs.shared.sha(root/'ref.png')))
 def tearDown(self):
  jobs.ROOT,jobs.RAW,jobs.EVIDENCE=self.old;self.tmp.cleanup()
 def reject(self,message,before=None,candidate='a'):
  with patch.object(jobs,'baseline',return_value=(self.initial,before or self.before)),patch.object(jobs.shared,'cli') as cli:
   with self.assertRaisesRegex(RuntimeError,message):jobs.submit(self.row,candidate)
   cli.assert_not_called()
 def test_frozen_budget_floor(self):self.reject('budget exhausted',dict(total=137,available=136,frozen=1))
 def test_existing_slot(self):
  jobs.shared.write(jobs.RAW/'fixture/a/intent.json',{});self.reject('Slot already used')
 def test_unknown_other_request(self):
  jobs.shared.write(jobs.RAW/'other/a/intent.json',{});self.reject('Unresolved earlier request')
 def test_external_spend(self):self.reject('Wallet differs',dict(total=149,available=149,frozen=0))
 def test_changed_reference(self):
  (jobs.ROOT/'ref.png').write_bytes(b'changed');self.reject('Exact reviewed reference missing')
 def test_second_candidate_needs_inspection(self):self.reject('Review candidate a',candidate='b')
 def test_prompt_limit(self):
  self.row['model_prompt']='x'*1025;self.reject('Prompt length invalid');self.assertFalse((jobs.RAW/'fixture/a/intent.json').exists())
 def test_unknown_timeout_locks_slot(self):
  with patch.object(jobs,'baseline',return_value=(self.initial,self.before)),patch.object(jobs.shared,'cli',side_effect=TimeoutError('unknown')) as cli:
   with self.assertRaises(TimeoutError):jobs.submit(self.row,'a')
   self.assertEqual(cli.call_count,1)
  self.assertTrue((jobs.RAW/'fixture/a/intent.json').exists());self.reject('Slot already used')
 def test_one_charge_one_recorded_id(self):
  with patch.object(jobs,'baseline',side_effect=[(self.initial,self.before),(self.initial,self.after)]),patch.object(jobs.shared,'cli',return_value=dict(generation_id='owned-id',status='queued')) as cli:
   jobs.submit(self.row,'a');self.assertEqual(cli.call_count,1)
  self.assertEqual(json.loads((jobs.RAW/'fixture/a/charge.json').read_text())['actual_committed_delta'],.5)

if __name__=='__main__':unittest.main()

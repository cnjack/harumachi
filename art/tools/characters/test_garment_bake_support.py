"""Small regression checks for preservation rules in the garment bake CLI."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np
from garment_bake_support import circular_weights, circular_weights_batch, extend_original_curve


class GarmentBakeChecks(unittest.TestCase):
    def test_periodic_weights_include_zero_and_wrap(self):
        phases=[0.,.25,.75]
        times=np.array([0.,.125,.5,.875,1.])
        batch=circular_weights_batch(phases,times)
        expected=np.array([[1,0,0],[.5,.5,0],[0,.5,.5],[.5,0,.5],[1,0,0]])
        np.testing.assert_array_equal(batch,expected)
        for at,row in zip(times,expected):np.testing.assert_array_equal(circular_weights(phases,at),row)
        self.assertLessEqual(int((batch!=0).sum(1).max()),2)

    def test_invalid_phase_order_is_rejected(self):
        with self.assertRaises(ValueError):circular_weights_batch([0.,.5,.5],[.3])

    def test_old_nonzero_curve_rows_and_bounded_function(self):
        times=np.array([0.,.3,1.],np.float32)
        values=np.array([[.1234,.3],[.73,-.1],[.2,.4]],np.float32)
        extra=np.array([.07,.22,.51,.91],np.float32)
        actual_times,actual,bound=extend_original_curve(times,values,extra)
        for t,value in zip(times,values):np.testing.assert_array_equal(actual[actual_times==t][0],value)
        self.assertLessEqual(bound['maximum_f32_ulp_error'],.5)
        dense=np.linspace(0,1,1001)
        for i in range(2):
            error=abs(np.interp(dense,times,values[:,i])-np.interp(dense,actual_times,actual[:,i]))
            self.assertLessEqual(float(error.max()),bound['old_weight_function_max_absolute_error']+1e-15)

    def test_wrong_source_identity_refuses_before_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/'bad.glb';source.write_bytes(b'not a GLB')
            output=root/'out'
            command=[sys.executable,str(Path(__file__).with_name('bake_periodic_garment_correctives.py')),'--input',str(source),'--controls',str(root),'--out',str(output),'--expected-source-sha256','0'*64,'--character','mio','--colour','blue','--curve-policy','resample','--clip','walk']
            result=subprocess.run(command,capture_output=True,text=True,timeout=20)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('Source GLB SHA256',result.stderr)
            self.assertFalse(output.exists())


if __name__=='__main__':unittest.main()

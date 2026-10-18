"""Small controls for final-packet conversion; no Godot or source assets."""
import copy,json,tempfile,unittest
from pathlib import Path
import numpy as np
from convert_native_sleeve_manifest import convert


class FinalPacketConversion(unittest.TestCase):
    def fixture(self):
        M=np.array([[0.,0,1],[0,1,0],[-1,0,0]])
        origin=np.array([2.,0,3]);local=np.array([.1,1.,.2])
        transform=np.r_[M@local+origin,M.T.ravel()].tolist()
        shapes={'Sleeve_Right':{'SleeveFit_stretch_375':.7}}
        frame={'frame':7,'clip':'stretch','clip_time':1.,'phase':.4,
            'model_basis':M.T.tolist(),'model_position':origin.tolist(),
            'bone_transforms':[transform],'blend_shape_values':shapes}
        sample={'applied_frame':7,'maximum_transform_difference_from_continuous':0,
                'bone_transforms':[transform],'blend_shape_values':copy.deepcopy(shapes)}
        return {'cases':[{'character':'mio','view':'front','sampling_failures':0,
            'bone_layout':[{'name':'joint'}],'frames':[frame],'full_bone_samples':[sample]}]}

    def call(self,doc):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'native.json';path.write_text(json.dumps(doc))
            return convert(path,'mio','fixture')

    def test_yaw_and_translation_removed_but_scalar_preserved(self):
        result=self.call(self.fixture());row=result['shots'][0]
        np.testing.assert_allclose(row['bones'][0]['position'],[.1,1,.2],atol=1e-14)
        np.testing.assert_allclose(row['bones'][0]['basis'],np.eye(3),atol=1e-14)
        self.assertEqual(row['blend_shape_values']['Sleeve_Right']['SleeveFit_stretch_375'],.7)

    def test_ack_scalar_mismatch_rejected(self):
        d=self.fixture();d['cases'][0]['full_bone_samples'][0]['blend_shape_values']['Sleeve_Right']['SleeveFit_stretch_375']=.8
        with self.assertRaisesRegex(ValueError,'same final callback'):self.call(d)

    def test_duplicate_ack_rejected(self):
        d=self.fixture();d['cases'][0]['full_bone_samples']*=2
        with self.assertRaisesRegex(ValueError,'Duplicate'):self.call(d)

    def test_unacknowledged_frame_excluded(self):
        d=self.fixture();frame=copy.deepcopy(d['cases'][0]['frames'][0]);frame['frame']=8;d['cases'][0]['frames'].append(frame)
        r=self.call(d);self.assertEqual(r['excluded_without_ack'],1);self.assertEqual(len(r['shots']),1)


if __name__=='__main__':unittest.main()

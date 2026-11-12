"""Guard the exact revision/image cleanup boundary with isolated fixtures."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('demo_cleanup', ROOT/'scripts/cleanup-demo-revisions.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def definition(n, digest):
    return {'taskDefinitionArn': m.FAMILY+str(n), 'containerDefinitions': [
        {'name':'app', 'image':m.PREFIX+digest,
         'healthCheck':{'command':['CMD-SHELL','exit 1'] if n in (4,5) else ['CMD','node','health.js']}}]}


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.defs = [definition(1,'bootstrap'),definition(3,'rollback'),definition(4,'demo4'),
                     definition(5,'demo5'),definition(6,'current')]
        self.images = [{'imageDigest':d,'imageManifestMediaType':'application/vnd.docker.distribution.manifest.v2+json'}
                       for d in ('bootstrap','rollback','demo4','demo5','current')]

    def test_only_broken_demo_revisions_and_their_images_selected(self):
        p=m.select(self.defs,[m.FAMILY+'6'],self.images)
        self.assertEqual(p['revisions'],sorted(m.RETIRED))
        self.assertEqual(p['imageDigests'],['demo4','demo5'])
        self.assertEqual(p['protectedDigests'],['bootstrap','current','rollback'])

    def test_referenced_demo_is_protected(self):
        with self.assertRaises(ValueError):m.select(self.defs,[m.FAMILY+'4'],self.images)

    def test_shared_digest_is_protected(self):
        self.defs.append(definition(7,'demo4'))
        with self.assertRaises(ValueError):m.select(self.defs,[],self.images)

    def test_shared_tag_reference_is_protected(self):
        self.images[2]['imageTags']=['shared']
        d=definition(7,'unused');d['containerDefinitions'][0]['image']=m.PREFIX.split('@')[0]+':shared'
        self.defs.append(d)
        with self.assertRaises(ValueError):m.select(self.defs,[],self.images)

    def test_unexpected_health_check_is_rejected(self):
        self.defs[2]['containerDefinitions'][0]['healthCheck']['command']=['CMD','true']
        with self.assertRaises(ValueError):m.select(self.defs,[],self.images)

    def test_manifest_index_is_not_deleted(self):
        self.images[2]['imageManifestMediaType']='application/vnd.oci.image.index.v1+json'
        with self.assertRaises(ValueError):m.select(self.defs,[],self.images)

    def test_changed_review_prevents_all_mutations(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'review.json';p.write_text('{}')
            with patch.object(m,'snapshot',return_value={'changed':True}), patch.object(m,'aws') as api:
                with patch('sys.argv',['cleanup','--execute','--review',str(p)]):
                    with self.assertRaises(ValueError):m.main()
                api.assert_not_called()

    def test_default_only_writes_review(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'review.json'
            with patch.object(m,'snapshot',return_value={'review':True}), patch.object(m,'aws') as api:
                with patch('sys.argv',['cleanup','--review',str(p)]):m.main()
                api.assert_not_called()
                self.assertEqual(json.loads(p.read_text()),{'review':True})


if __name__=='__main__':unittest.main()

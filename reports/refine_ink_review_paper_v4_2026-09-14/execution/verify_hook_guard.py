#!/usr/bin/env python3
"""Test the proposed opt-out in memory with all repository actions mocked."""
from pathlib import Path
import hashlib,json,tempfile
from unittest.mock import Mock
P=Path(__file__).resolve().parent
info=json.loads((P/'hook_guard_proposal.json').read_text())
source=Path(info['path']).read_text()
assert hashlib.sha256(source.encode()).hexdigest()==info['original_sha256']
anchor='    remotes = github_push_remotes(root)\n'
assert source.count(anchor)==1
insert='    # Repository-local opt-out for work that explicitly prohibits checkpoints.\n    if (root / ".codex-no-auto-checkpoint").is_file():\n        eprint(f"{root}: checkpoint automatico desativado por marcador local.")\n        return 0\n\n'
proposal=source.replace(anchor,insert+anchor)
assert hashlib.sha256(proposal.encode()).hexdigest()==info['proposal_sha256']
ns={'__name__':'guard_test_only'}
exec(compile(proposal,'proposed_hook.py','exec'),ns)
with tempfile.TemporaryDirectory(prefix='hook-guard-test-') as folder:
 root=Path(folder)
 ns['load_payload']=lambda:{'hook_event_name':'Stop','cwd':folder}
 ns['repo_root']=lambda _:root
 ns['eprint']=Mock()
 forbidden=Mock(side_effect=AssertionError('No repository actions allowed'))
 ns['github_push_remotes']=forbidden
 ns['git']=forbidden
 (root/info['marker']).write_text('test only\n')
 assert ns['main']()==0
 forbidden.assert_not_called()
 (root/info['marker']).unlink()
 remotes=Mock(return_value=[])
 ns['github_push_remotes']=remotes
 assert ns['main']()==0
 remotes.assert_called_once_with(root)
 forbidden.assert_not_called()
report={'status':'PASS','marker_skips_all_mutating_actions':True,'unmarked_repo_preserves_original_branch':True,'global_hook_changed':False,'git_actions_executed':False,'test_scope':'In-memory proposed source; mocked repository discovery and all Git actions'}
(P/'hook_guard_test.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))

const fs = require('node:fs');
const path = require('node:path');
const newline = String.fromCharCode(10);
const esc = (value) => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
module.exports = (results) => {
  const cases = results.testResults.flatMap((suite) => suite.testResults.map((test) => {
    const a = 'classname="' + esc(suite.testFilePath) + '" name="' + esc(test.fullName) + '"';
    if (test.status === 'failed') return '  <testcase ' + a + '><failure message="Test failed"><![CDATA[' + test.failureMessages.join(newline) + ']]></failure></testcase>';
    if (test.status === 'pending' || test.status === 'todo') return '  <testcase ' + a + '><skipped/></testcase>';
    return '  <testcase ' + a + '/>';
  }));
  const report = ['<?xml version="1.0" encoding="UTF-8"?>', '<testsuite name="jest" tests="' + results.numTotalTests + '" failures="' + results.numFailedTests + '" skipped="' + results.numPendingTests + '">', ...cases, '</testsuite>', ''].join(newline);
  fs.mkdirSync(path.join(process.cwd(), 'test-results'), { recursive: true });
  fs.writeFileSync(path.join(process.cwd(), 'test-results', 'junit.xml'), report, 'utf8');
  return results;
};

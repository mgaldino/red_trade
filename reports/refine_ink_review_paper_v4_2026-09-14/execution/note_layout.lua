function Code(el)
  if not FORMAT:match('latex') then return nil end
  local escaped = {}
  local run = 0
  for _, cp in utf8.codes(el.text) do
    local c = utf8.char(cp)
    local replacements = {['\\']='\\textbackslash{}', ['{']='\\{', ['}']='\\}', ['_']='\\_', ['%']='\\%', ['#']='\\#', ['&']='\\&', ['$']='\\$', ['^']='\\textasciicircum{}', ['~']='\\textasciitilde{}'}
    table.insert(escaped, replacements[c] or c)
    run = run + 1
    if c == '/' or c == '_' or c == '-' or run >= 8 then
      table.insert(escaped, '\\allowbreak{}')
      run = 0
    end
  end
  return pandoc.RawInline('latex', '\\texttt{' .. table.concat(escaped) .. '}')
end

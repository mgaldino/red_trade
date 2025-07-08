-- affiliations.lua  –– footnote affiliation for each author
-- Compatible with PDF (LaTeX) and Word (docx) output.

local pandoc = require 'pandoc'

-- Convert either a string or an Inline list to Inlines
local function toInlines(x)
  if pandoc.utils.type(x) == 'Inlines' then
    return x
  elseif type(x) == 'string' then
    return pandoc.Inlines { pandoc.Str(x) }
  elseif type(x) == 'table' then         -- e.g. MetaInlines
    return pandoc.Inlines(x)
  else
    return pandoc.Inlines{}
  end
end

function Meta(meta)
  if not meta.author then return meta end

  for i, a in ipairs(meta.author) do
    if type(a) == 'table' and a.affiliation then
      -- make a footnote from the affiliation text
      local fn   = pandoc.Note { pandoc.Para(toInlines(a.affiliation)) }

      -- ensure author name is Inlines, then append the footnote marker
      local name = toInlines(a.name)
      name:insert(fn)

      -- write back & clean up
      a.name        = name
      a.affiliation = nil
      meta.author[i] = a
    end
  end
  return meta
end
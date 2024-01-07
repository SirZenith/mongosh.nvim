local M = {}

-- get all available databases' name
M.CMD_LIST_DBS = [[
const result = db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name)
JSON.stringify(result)
]]

-- get all available collections' name
M.CMD_LIST_COLLECTIONS = [[
JSON.stringify(db.getCollectionNames())
]]

-- query template with `$q` as query script place holder
M.TEMPLATE_QUERY = [[
// https://github.com/nodejs/node/issues/6456
try {
  process.stdout._handle.setBlocking(true);
} catch (_e) {}

config.set('inspectDepth', Infinity);
const q = ${query};
if (q && typeof q.toArray === 'function') q = q.toArray();

const json = EJSON.stringify(q, null, ${indent})
print(json)
]]

-- query template for finding one document with `_id`
M.TEMPLATE_FIND_ONE = [[
db["${collection}"].findOne({ _id: EJSON.deserialize(${id}) })
]]

-- editing template for replaceOne call, user should define following variable
-- in the snippet provided:
--
-- - `collection`, string value for specifying which collection to use
-- - `id`, `_id` value of target document
-- - `replacement`, new document value to use as `replaceOne` argument
M.TEMPLATE_EDIT = [[
${snippet}

const result = db[collection].replaceOne( { _id: EJSON.deserialize(id) }, replacement)

const json = EJSON.stringify(result, null, ${indent})
print(json)
]]

-- snippet template for querying
M.SNIPPET_QUERY = [[
db["${collection}"].find({})
]]

-- snippet template for document editing
M.SNIPPET_EDIT = [[
// Edit document value here
const collection = "${collection}"
const id = ${id}
const replacement = EJSON.deserialize(
${document}
)
]]

return M

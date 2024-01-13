local M = {}

-- ----------------------------------------------------------------------------
-- Command

-- get all available databases' name
M.CMD_LIST_DBS = [[
const result = db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name);
JSON.stringify(result);
]]

-- get all available collections' name
M.CMD_LIST_COLLECTIONS = [[
JSON.stringify(db.getCollectionNames());
]]

-- ----------------------------------------------------------------------------
-- Template

-- Query template with `${query}` as query script place holder.
-- Query snippet should define following variable(s):
--
-- - `result`, any value, this  will be treated as query result, and gets printed.
M.TEMPLATE_QUERY = [[
// https://github.com/nodejs/node/issues/6456
try {
    process.stdout._handle.setBlocking(true);
} catch (_e) {}

config.set('inspectDepth', Infinity);

${query}

{
    const requirement = { result };
    let err = null;
    for (const [name, value] of Object.entries(requirement)) {
        if (typeof value === 'undefined') {
            err = `variable ${name} is undefined`;
        }
    }

    if (err) {
        print(err);
    } else {
        let output = result;
        if (output && typeof output.toArray === 'function') {
            output = output.toArray();
        }

        const json = EJSON.stringify(output, null, ${indent});
        print(json);
    }
}
]]

-- editing template for replaceOne call, user should define following variable
-- in the snippet provided:
--
-- - `collection`, string value for specifying which collection to use
-- - `id`, `_id` value of target document
-- - `replacement`, new document value to use as `replaceOne` argument
M.TEMPLATE_EDIT = [[
${snippet}

{
    const requirement = { collection, id, replacement };
    let err = null;
    for (const [name, value] of Object.entries(requirement)) {
        if (typeof value === 'undefined') {
            err = `variable ${name} is undefined`;
        }
    }

    if (err) {
        print(err);
    } else {
        const result = db[collection].replaceOne({ _id: EJSON.deserialize(id) }, replacement);
        const json = EJSON.stringify(result, null, ${indent});
        print(json);
    }
}
]]

-- updatae template for `updateOne` call, user should define following variable
-- in the snippet provided:
--
-- - `collection`, string value for specifying which collection to use
-- - `id`, `_id` value of target document
-- - `replacement`, new document value to use as `replaceOne` argument
M.TEMPLATE_UPDATE_ONE = [[
${snippet}

{
    const requirement = { collection, id, replacement };
    let err = null;
    for (const [name, value] of Object.entries(requirement)) {
        if (typeof value === 'undefined') {
            err = `variable ${name} is undefined`;
        }
    }

    if (err) {
        print(err);
    } else {
        const result = db[collection].updateOne({ _id: EJSON.deserialize(id) }, { $set: replacement })
        const json = EJSON.stringify(result, null, ${indent})
        print(json)
    }
}
]]

-- ----------------------------------------------------------------------------
-- Snippet

-- snippet template for querying
M.SNIPPET_QUERY = [[
const collection = "${collection}"
const filter = {}
const projection = {}

// Variable `result` will be treated as snippet output
const result = db[collection].find(filter, projection)
]]

-- query template for finding one document with `_id`
M.SNIPPET_FIND_ONE = [[
const collection = "${collection}"
const id = ${id}
const projection = ${projection}

// Variable `result` will be treated as snippet output
const result = db[collection].findOne({ _id: EJSON.deserialize(id) }, projection)
]]

-- snippet template for document editing
M.SNIPPET_EDIT = [[
const collection = "${collection}"
const id = ${id}

// Edit your document value
const replacement = EJSON.deserialize(${document})
]]

return M

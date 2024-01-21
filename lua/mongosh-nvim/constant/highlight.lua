local M = {}

M.HighlightGroup = {
    Normal                  = "MongoshNormal",

    -- ------------------------------------------------------------------------
    -- Sidebar
    HostName                = "MongoshHostName",
    HostSymbol              = "MongoshHostSymbol",

    DatabaseName            = "MongoshDatabaseName",
    DatabaseSymbol          = "MongoshDatabaseSymbol",

    CollectionName          = "MongoshCollectionName",
    CollectionSymbol        = "MongoshCollectionSymbol",

    CollectionLoading       = "MongoshCollectionLoading",
    CollectionLoadingSymbol = "MongoshCollectionLoadingSymbol",

    -- ------------------------------------------------------------------------
    -- Card View
    TreeNormal              = "MongoshTreeNormal",
    TreeIndented            = "MongoshTreeIndented",

    ValueTypeName           = "MongoshValueTypeName",

    ValueArray              = "MongoshValueArray",
    ValueBoolean            = "MongoshValueBoolean",
    ValueNull               = "MongoshValueNull",
    ValueNumber             = "MongoshValueNumber",
    ValueString             = "MongoshValueString",
    ValueObject             = "MongoshValueObject",
    ValueOmited             = "MongoshValueOmited",
    ValueRegex              = "MongoshValueRegex",
    ValueUnknown            = "MongoshValueUnknown",
}

return M

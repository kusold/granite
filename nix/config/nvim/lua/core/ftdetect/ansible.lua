vim.filetype.add({
  pattern = {
    [".*/tasks/.*.ya?ml"] = "yaml.ansible",
    [".*/roles/.*.ya?ml"] = "yaml.ansible",
    [".*/handlers/.*.ya?ml"] = "yaml.ansible",
    [".*/group_vars/.*.ya?ml"] = "yaml.ansible",
    [".*/host_vars/.*.ya?ml"] = "yaml.ansible",
    [".*/ansible/.*.ya?ml"] = "yaml.ansible",
  },
})

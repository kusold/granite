return {
  {
    -- Easy commenting
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end,
  },
  {
    -- Provides sane-folding that looks at the actual code
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    config = function()
      require("ufo").setup()
    end,
  },
  {
    -- Match indentation to file
    "nmac427/guess-indent.nvim",
    config = function()
      require("guess-indent").setup()
    end,
  },
}

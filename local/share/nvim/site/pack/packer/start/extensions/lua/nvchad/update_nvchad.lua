local function update()
  -- in all the comments below, config means user config
  local config_path = vim.fn.stdpath "config"
  local utils = require "nvchad"
  local echo = utils.echo
  local current_config = require("core.utils").load_config()
  local update_url = current_config.options.nvChad.update_url or "https://github.com/NvChad/NvChad"
  local update_branch = current_config.options.nvChad.update_branch or "main"
  local current_sha, backup_sha, remote_sha = "", "", ""
  local breaking_change_patterns = { "breaking.*change" }

  -- on failing, restore to the last repo state, including untracked files
  local function restore_repo_state()
    utils.cmd(
      "git -C "
      .. config_path
      .. " reset --hard "
      .. current_sha
      .. " ; git -C "
      .. config_path
      .. " cherry-pick -n "
      .. backup_sha
      .. " ; git reset",
      false
    )
  end

  -- get the current sha of the remote HEAD
  local function get_remote_head(branch)
    local result = utils.cmd("git -C " .. config_path .. " ls-remote --heads origin " .. branch, true)
    if result then
      return result:match "(%w*)"
    end
    return ""
  end

  -- get the current sha of the local HEAD
  local function get_local_head()
    local result = utils.cmd("git -C " .. config_path .. " rev-parse HEAD", false)
    if result then
      return result:match "(%w*)"
    end
    return ""
  end

  -- check if the NvChad directory is a valid git repo
  local function validate_dir()
    local valid = true
    -- save the current sha of the local HEAD
    current_sha = get_local_head()
    -- check if the config folder is a valid git directory
    if current_sha ~= "" then
      -- create a tmp snapshot of the current repo state
      utils.cmd("git -C " .. config_path .. " commit -a -m 'tmp'", false)
      backup_sha = get_local_head()
      if backup_sha == "" then
        valid = false
      end
    else
      valid = false
    end
    if not valid then
      restore_repo_state()
      echo { { "Error: " .. config_path .. " is not a valid git directory.\n", "ErrorMsg" } }
      return false
    end
    return true
  end

  -- returns the latest commit message in the git history
  local function get_last_commit_message()
    local result = utils.cmd("git -C " .. config_path .. " log -1 --pretty=%B", false)
    if result then
      return result:match "(%w*)"
    end
    return ""
  end

  -- print a progress message
  local function print_progress_percentage(text, text_type, current, total, clear)
    local percent = math.floor(current / total * 100) or 0
    if clear then
      utils.clear_last_echo()
    end
    echo { { text .. " (" .. current .. "/" .. total .. ") " .. percent .. "%", text_type } }
  end

  -- create a dictionary of human readable strings
  local function get_human_readables(count)
    local human_readable_dict = {}
    human_readable_dict["have"] = count > 1 and "have" or "has"
    human_readable_dict["commits"] = count > 1 and "commits" or "commit"
    human_readable_dict["change"] = count > 1 and "changes" or "change"
    return human_readable_dict
  end

  -- get all commits between two points in the git history as a list of strings
  local function get_commit_list_by_hash_range(start_hash, end_hash)
    local commit_list_string = utils.cmd(
      "git -C "
      .. config_path
      .. " log --oneline --no-merges --decorate --date=short --pretty='format:%ad: %h %s' "
      .. start_hash
      .. ".."
      .. end_hash,
      true
    )
    if commit_list_string == nil then
      return nil
    end
    return vim.fn.split(commit_list_string, "\n")
  end

  -- filter string list by regex pattern list
  local function filter_commit_list(commit_list, patterns)
    local counter = 0
    return vim.tbl_filter(function(line)
      -- update counter and print current progress
      counter = counter + 1
      print_progress_percentage("Analyzing commits...", "String", counter, #commit_list, true)
      -- normalize current commit
      local normalized_line = string.lower(line)
      -- check if the commit message matches any of the patterns
      for _, pattern in ipairs(patterns) do
        -- match the pattern against the normalized commit message
        if vim.fn.match(normalized_line, pattern) ~= -1 then
          return true
        end
      end
      return false
    end, commit_list), counter or nil, counter
  end

  -- prepare the string representation of a commit list and return a list of lists to use with echo
  local function prepare_commit_table(commit_list)
    local output = { { "" } }
    for _, line in ipairs(commit_list) do
      -- split line into date hash and message. Expected format: "yyyy-mm-dd: hash message"
      local commit_date, commit_hash, commit_message = line:match "(%d%d%d%d%-%d%d%-%d%d): (%w+)(.*)"
      -- merge commit messages into one output array to minimize echo calls
      vim.list_extend(output, {
        { "    " },
        { tostring(commit_date) },
        { " " },
        { tostring(commit_hash), "WarningMsg" },
        { tostring(commit_message), "String" },
        { "\n" },
      })
    end
    return output
  end

  -- check for breaking changes in the current branch
  local function check_for_breaking_changes(current_head, remote_head)
    -- if the remote HEAD is equal to the current HEAD we are already up to date
    if remote_head == current_head then
      utils.clear_last_echo()
      echo {
        { "You are already up to date with ", "String" },
        { "" .. update_branch .. "" },
        { ". There is nothing to do!", "String" },
      }
      return false
    end

    utils.clear_last_echo()
    echo { { "Url: ", "Title" }, { update_url }, { "\nBranch: ", "Title" }, { update_branch },
      { "\n\n" } }

    print_progress_percentage("Fetching new changes from remote...", "String", 1, 2, false)

    -- fetch remote silently
    local fetch_status = utils.cmd(
      "git -C "
      .. config_path
      .. " fetch --quiet --prune --no-tags "
      .. "--no-recurse-submodules origin "
      .. update_branch,
      true
    )
    if fetch_status == nil then
      restore_repo_state()
      echo { { "Error: Could not fetch remote changes.", "ErrorMsg" } }
      return false
    end

    print_progress_percentage("Analyzing commits...", "String", 2, 2, true)

    -- get all new commits
    local new_commit_list = get_commit_list_by_hash_range(current_head, remote_head)

    -- if we did not receive any new commits, we encountered an error
    if new_commit_list == nil or #new_commit_list == 0 then
      utils.clear_last_echo()
      echo {
        {
          "\nSomething went wrong. No new commits were received even though the remote's HEAD differs from the "
              .. "currently checked out HEAD.",
          "Title",
        },
        { "\n\nWould you like to reset NvChad to the remote's HEAD? Local changes will be lost! " ..
            "[y/N]", "WarningMsg" },
      }
      local continue = string.lower(vim.fn.input "-> ") == "y"
      echo { { "\n\n", "String" } }

      if continue then
        return nil, nil
      else
        restore_repo_state()
        echo { { "Update cancelled!", "Title" } }
        return false
      end
    end

    -- get human redable wording
    local hr = get_human_readables(#new_commit_list)

    -- create a summary of the new commits
    local new_commits_summary_list = prepare_commit_table(new_commit_list)
    local new_commits_summary = {
      { "There ", "Title" },
      { hr["have"], "Title" },
      { " been", "Title" },
      { " " .. #new_commit_list .. " " },
      { "new ", "Title" },
      { hr["commits"], "Title" },
      { " since the last update:\n", "Title" },
    }
    vim.list_extend(new_commits_summary, new_commits_summary_list)
    vim.list_extend(new_commits_summary, { { "\n", "String" } })

    utils.clear_last_echo()
    echo(new_commits_summary)

    -- check if there are any breaking changes
    local breaking_changes, counter = filter_commit_list(new_commit_list, breaking_change_patterns)

    if #breaking_changes == 0 then
      print_progress_percentage("No breaking changes in commit list - Analyzed", "Title",
        counter, #new_commit_list, true)
    else
      print_progress_percentage("Analyzing commits... Done", "String",
        counter, #new_commit_list, true)
    end

    -- if there are breaking changes, print a list of them
    if #breaking_changes > 0 then
      hr = get_human_readables(#breaking_changes)
      local breaking_changes_message = {
        { "\nFound", "Title" },
        { " " .. #breaking_changes .. " " },
        { "potentially breaking ", "Title" },
        { hr["change"], "Title" },
        { ":\n", "Title" },
      }
      vim.list_extend(breaking_changes_message, prepare_commit_table(breaking_changes))
      echo(breaking_changes_message)

      -- ask the user if they would like to continue with the update
      echo { { "\nWould you still like to continue with the update? [y/N]", "WarningMsg" } }
      local continue = string.lower(vim.fn.input "-> ") == "y"
      echo { { "\n\n", "String" } }

      if continue then
        return true, true
      else
        restore_repo_state()
        echo { { "Update cancelled!", "Title" } }
        return false
      end
    else
      -- if there are no breaking changes, just update
      echo { { "\n", "String" } }
      return true
    end
  end

  -- ask the user if they want to run PackerSync
  local function ask_if_packer_sync()
    -- prompt the user to execute PackerSync
    echo { { "Would you like to run ", "WarningMsg" }, { "PackerSync" },
      { " after the update has completed?\n", "WarningMsg" },
      { "Not running ", "WarningMsg" }, { "PackerSync" }, { " may break NvChad! ", "WarningMsg" },
      { "[y/N]", "WarningMsg" } }

    local ans = string.lower(vim.fn.input "-> ") == "y"
    return ans
  end

  -- reset the repo to the remote's HEAD and clean up
  local function reset_to_remote_head()
    -- reset to remote HEAD
    local reset_status = utils.cmd(
      "git -C "
      .. config_path
      .. " reset --hard origin/" .. update_branch,
      true
    )

    if reset_status == nil then
      restore_repo_state()
      utils.clear_last_echo()
      echo { { "Error: Could not reset to remote HEAD.", "ErrorMsg" } }
      return false
    end

    utils.clear_last_echo()
    echo { { "Reset to remote HEAD successful!\n\n", "Title" }, { reset_status, "String" },
      { "\n", "String" } }

    -- clean up the repo
    local clean_status = utils.cmd(
      "git -C "
      .. config_path
      .. " clean -f -d",
      true
    )

    if clean_status == nil then
      restore_repo_state()
      echo { { "Error: Could not clean up the repo.", "ErrorMsg" } }
      return false
    end

    echo { { "Cleanup successful!\n\n", "Title" } }

    return true
  end

  -- if the updater failed to remove the last tmp commit remove it
  local function check_for_leftover_tmp_commit()
    local last_commit_message = get_last_commit_message()
    if last_commit_message:match("^tmp$") then
      echo { { "Removing tmp commit. This has not been removed properly after the last " ..
          "update. Cleaning up...\n\n", "WarningMsg" } }
      -- push unstaged changes to stash if there are any
      local result = utils.cmd("git -C " .. config_path .. " stash", true)
      -- remove the tmp commit
      utils.cmd("git -C " .. config_path .. " reset --hard HEAD~1", false)
      -- if local changes were stashed, try to reapply them
      if not result:match("No local changes to save") then
        echo { { "Local changes outside of the custom directory detected. They have be stashed " ..
            "using \"git stash\"!\n\n", "WarningMsg" } }
        -- force pop the stash
        local stash_pop = utils.cmd("git -C " .. config_path .. " stash show -p | git -C " ..
          config_path .. " apply && git -C " .. config_path .. " stash drop", true)
        if stash_pop then
          echo { { "Local changes have been restored succesfully.\n", "WarningMsg" } }
        else
          echo { { "\nApplying stashed changes to the NvChad directory failed, please resolve the " ..
              "conflicts manually and use \"git stash pop\" to restore or \"git stash drop\" to " ..
              "discard them!\n", "WarningMsg" } }
        end
      end
      echo { { "\n" } }
    end
  end

  -- THE UPDATE PROCEDURE BEGINS HERE

  -- check if the last tmp commit was properly removed, if not remove it
  check_for_leftover_tmp_commit()

  local valid_git_dir = validate_dir()
  local continue, skip_confirmation = false, false

  -- return if the directory is not a valid git directory
  if not valid_git_dir then return end

  echo { { "Checking for updates...", "String" } }

  -- get the current sha of the remote HEAD
  remote_sha = get_remote_head(update_branch)
  if remote_sha == "" then
    restore_repo_state()
    echo { { "Error: Could not fetch remote HEAD sha.", "ErrorMsg" } }
    return
  end

  continue, skip_confirmation = check_for_breaking_changes(current_sha, remote_sha)

  if continue == nil and skip_confirmation == nil then
    echo { { "Resetting to remote HEAD...", "Title" } }

    if not reset_to_remote_head() then
      restore_repo_state()
      echo { { "\nError: NvChad Update failed.", "ErrorMsg" } }
      return false
    end

    utils.clear_last_echo()
    echo { { "NvChad's HEAD has successfully been reset to ", "Title" },
      { update_branch }, { ".\n\n", "Title" } }

    valid_git_dir = validate_dir()
    if not valid_git_dir then return end
  elseif not continue then
    return
  end

  -- ask the user for confirmation to update because we are going to run git reset --hard
  if backup_sha ~= current_sha then
    echo {
      { "Warning\n  Modification to repo files detected.\n\n  Updater will run", "WarningMsg" },
      { " git reset --hard " },
      {
        "in config folder, so changes to existing repo files except ",
        "WarningMsg",
      },

      { "lua/custom folder" },
      { " will be lost!\n", "WarningMsg" },
    }
    skip_confirmation = false
  else
    echo { { "No conflicting changes outside of the custom folder, ready to update.", "Title" } }
  end

  if skip_confirmation then
    echo { { "\n", "String" } }
  else
    echo { { "\nUpdate NvChad? [y/N]", "WarningMsg" } }
    local ans = string.lower(vim.fn.input "-> ") == "y"

    echo { { "\n\n", "String" } }
    if not ans then
      restore_repo_state()
      echo { { "Update cancelled!", "Title" } }
      return
    end
  end

  local packer_sync = ask_if_packer_sync()

  -- function that will executed when git commands are done
  local function update_exit(_, code)
    -- close the terminal buffer only if update was success, as in case of error, we need the error message
    if code == 0 then
      local summary = {}
      -- check if there are new commits
      local applied_commit_list = get_commit_list_by_hash_range(current_sha, get_local_head())
      if applied_commit_list ~= nil and #applied_commit_list > 0 then
        vim.list_extend(summary, { { "Applied Commits:\n", "Title" } })
        vim.list_extend(summary, prepare_commit_table(applied_commit_list))
      else -- no new commits
        vim.list_extend(summary, { { "Could not create a commit summary.\n", "WarningMsg" } })
      end
      vim.list_extend(summary, { { "\nNvChad succesfully updated.\n", "String" } })
      -- print the update summary
      vim.cmd "bd!"
      echo(summary)
      if packer_sync then
        vim.cmd [[PackerSync]]
      end
    else
      restore_repo_state()
      echo { { "Error: NvChad Update failed.\n\n", "ErrorMsg" },
        { "Local changes were restored." } }
    end
  end

  -- reset in case config was modified
  utils.cmd("git -C " .. config_path .. " reset --hard " .. current_sha, true)
  -- use --rebase, to not mess up if the local repo is outdated
  local update_script = table.concat({
    "git pull --set-upstream",
    update_url,
    update_branch,
    "--rebase",
  }, " ")

  -- open a new buffer
  vim.cmd "new"
  -- finally open the pseudo terminal buffer
  vim.fn.termopen(update_script, {
    -- change dir to config path so we don't need to move in script
    cwd = config_path,
    on_exit = update_exit,
  })
end

return update

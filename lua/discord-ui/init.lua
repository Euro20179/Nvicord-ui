local discord = require "discord"
local config = require"discord.config"

local members = require'discord.resources.members'

local events = require"discord.events"

local _M = {}

local message_extmarks = {}

local role_hls = {}

local data = {}

_M.setup = function (opts)
    discord.setup(opts)

    local discord_hl_ns = vim.api.nvim_create_namespace("discord")
    local discord_msg_ns = vim.api.nvim_create_namespace("discord_messages")

    data.discord_hl_ns = discord_hl_ns
    data.discord_msg_ns = discord_msg_ns

    vim.cmd.highlight("DiscordStrike cterm=strikethrough gui=strikethrough")

    vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "discord://*",
        callback = function()
            local name = vim.api.nvim_buf_get_name(0)
            if not discord.has_started() then
                discord.start(name)
            else
                discord.open_uri(name)
            end
        end
    })

    events.listen("TYPING_START", function (event)
        local member = members.get_member_in_server(event.guild_id, event.user_id)
        if member ~= nil then
            vim.notify(member.user.global_name .. " has started typing", vim.log.levels.INFO, {})
        end
    end)

    events.listen(events.Events.READY, function(event)
        vim.notify("You are logged in", vim.log.levels.INFO, {})
    end)

    --updates the highlight of a message in a highlight buffer to have strikethrough
    events.listen(events.Events.MESSAGE_DELETE, function(MESSAGE_DELETE)
        local msgObj = MESSAGE_DELETE.d
        local guild_id = msgObj.guild_id
        if guild_id == nil then
            return
        end
        local buffers = discord.get_channel_buffers(guild_id, msgObj.channel_id)

        local out = buffers.output_buf

        if out == nil then
            return
        end

        local msg_extmark = message_extmarks[msgObj.id]

        local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(out, data.discord_msg_ns, msg_extmark[1], {})

        vim.api.nvim_buf_set_extmark(out, data.discord_hl_ns, extmark_pos[1], 0, {
            end_row = extmark_pos[1] + msg_extmark[2],
            hl_group = "DiscordStrike"
        })
    end)

    --sends message to output bufferr
    events.listen(events.Events.MESSAGE_CREATE, function(MESSAGE_CREATE)
            local msgObj = MESSAGE_CREATE.d
            local guild_id = msgObj.guild_id
            if guild_id == nil and msgObj.author.id ~= config.user_id then
                discord.dm_notify(msgObj)
                return
            end
            local displayName = vim.NIL

            local color = "000000"

            if msgObj.member then
                displayName = msgObj.member.nick
            end

            if displayName == vim.NIL then
                displayName = msgObj.author.username
            end
            if displayName == vim.NIL then
                displayName = "<UNKNOWN>"
            end

            local contentLines = vim.split(msgObj.content, "\n")
            local name_part = "@" .. displayName
            local lines = { name_part .. ": " .. contentLines[1] }
            for i = 2, #contentLines do
                lines[i] = contentLines[i]
            end

            for i = 1, #msgObj.attachments do
                lines[#lines + 1] = "[" .. msgObj.attachments[i].filename .. "]" .. "(" .. msgObj.attachments[i].url .. ")"
            end

            local buffers = discord.get_channel_buffers(guild_id, msgObj.channel_id)

            if buffers.output_buf == nil then
                return
            end

            if msgObj.member.roles then
                members._add_member_to_cache(msgObj.member, msgObj.author.id)
                color = members.get_member_color_as_hex(guild_id, msgObj.author.id)
            end

            if not role_hls[color] then
                vim.api.nvim_set_hl(data.discord_hl_ns, "Discord" .. color, {
                    link = "Normal"
                })
                vim.cmd.highlight("Discord" .. color .. " guifg=#" .. color)
                role_hls[color] = true
            end

            vim.api.nvim_buf_set_lines(buffers.output_buf, -1, -1, false, lines)

            local line_count = vim.api.nvim_buf_line_count(buffers.output_buf)

            local message_extmark = vim.api.nvim_buf_set_extmark(buffers.output_buf, data.discord_msg_ns, line_count - 1, 0,
                {})

            message_extmarks[msgObj.id] = {
                message_extmark,
                #lines
            }

            vim.api.nvim_buf_add_highlight(buffers.output_buf, data.discord_hl_ns, "Discord" .. color, line_count - #lines, 0,
                #name_part)

            local output_win = discord.get_channel_output_win("discord://id=" .. guild_id .. "/id=" .. msgObj.channel_id)
            if output_win then
                vim.api.nvim_win_set_cursor(output_win, { vim.api.nvim_buf_line_count(buffers.output_buf), 0 })
            end
        end)
end

local function _display_channel(inBuf, outBuf)
    vim.cmd.tabnew()
    vim.api.nvim_win_set_buf(0, inBuf)
    vim.api.nvim_open_win(outBuf, false, {
        split = 'above',
        win = 0
    })
end

---Opens a new tab with a split, top window is output, bottom window is input
---
---if both inBuf AND outBuf are provided
---this function simply opens a new tab and splits with topsplit being output buf
---bottom split being input buf
---@param inBuf buffer
---@param outBuf buffer
_M.display_channel = function(inBuf, outBuf)
    --if both are provided simply open a tab to display the buffers
    --
    --this makes it easy to call open_channel and put the result directly into display_channel
    if inBuf ~= nil and outBuf ~= nil then
        _display_channel(inBuf, outBuf)
        return
    end

    local chans = vim.iter(vim.api.nvim_list_bufs())
        :filter(vim.api.nvim_buf_is_valid)
        :map(vim.api.nvim_buf_get_name)
        :filter(function(name)
            return vim.startswith(name, "discord://")
        end)
        :totable()

    vim.ui.select(chans, {}, function(item)
        local result = discord.parse_discord_uri(item)
        if result == nil then
            return
        end
        local server, channel, buf_type = discord.unpack_uri_result(result)

        local bufPair = discord.find_server_channel_buf_pair(server.id, channel.id)

        _display_channel(bufPair.IN, bufPair.OUT)
    end)
end

_M.open_channel_list = function (server_id)
    if server_id == nil then
        server_id = discord.get_focused_server_id()
    end
    if server_id == nil then
        vim.notify("Could not open channel list, unknown server", vim.log.levels.ERROR)
        return
    end

    local channels = discord.channels.get_channels_in_server(server_id)
    if channels == nil then
        vim.notify("No channels", vim.log.levels.ERROR, {})
        return
    end

    local chan_buf = vim.api.nvim_create_buf(true, false)

    vim.api.nvim_set_option_value("filetype", "markdown", {
        buf = chan_buf
    })

    local chan_win = vim.api.nvim_open_win(chan_buf, true, {
        split = 'left'
    })

    for i = 1, #channels do
        --set_lines is 0indexed, i starts at 1, so subtract 1
        local chan = channels[i]
        if chan.type ~= 0 then
            goto continue
        end
        local link = "discord://id=" .. server_id .. "/" .. chan.name
        vim.api.nvim_buf_set_lines(chan_buf, i - 1, i - 1 + 1, false, { "[" .. channels[i].name .. "](" .. link .. ")" })
        ::continue::
    end
end

return _M

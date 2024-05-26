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
            if not data.started then
                discord.start(name)
            else
                discord.open_uri(name)
            end
        end
    })


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

return _M

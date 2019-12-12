--[[
Copyright (c) 2019 Alexander Lindenstruth

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

WebBanking {
	version = 2.0,
	country = "de",
	url = "https://www.deutschlandcard.de",
	services    = {"Deutschlandcard-Punkte"},
	description = string.format(MM.localizeText("Get points of %s"), "DeutschlandCard account")
}

function SupportsBank (protocol, bankCode)
	return bankCode == "Deutschlandcard-Punkte" and protocol == ProtocolWebBanking
end

-- Data Converters
local monthMappingTable = {
	[" Januar "] = "01.",
	[" Februar "] = "02.",
	[" März "] = "03.",
	[" April "] = "04.",
	[" Mai "] = "05.",
	[" Juni "] = "06.",
	[" Juli "] = "07.",
	[" August "] = "08.",
	[" September "] = "09.",
	[" Oktober "] = "10.",
	[" November "] = "11.",
	[" Dezember "] = "12.",
}

-- convert date strings like 2019-10-05T00:00:00 to posix timestamps 
local function DatestringToPosixTime(date)
	for key,value in pairs(monthMappingTable) do 
		date = date:gsub(key,value)
	end
	year, month, day = string.match(date,"(%d%d%d%d)%-(%d%d)%-(%d%d)")
	return os.time{year=year, month=month, day=day, hour=0}
end

local connection
local accountNumber
local requestHeaders = {
    ["Accept"] = "application/json",
}

function InitializeSession (protocol, bankCode, username, username2, password, username3)
	accessToken = ""
	connection = Connection()
	local url = "https://www.deutschlandcard.de/api/v1/auth/connect/token"
	local formData = "{\"grant_type\":\"password\",\"response_type\":\"id_token token\",\"scope\":\"deutschlandcardapi offline_access\",\"audience\":\"deutschlandcardapi\",\"username\":\"" .. username .. "\",\"password\":\"" .. password .. "\"}"
	local content, charset, mimeType, filename, headers = connection:request("POST", url, formData, "application/json; charset=UTF-8")
	local fields = JSON(content):dictionary()
	accountNumber = username
	local accessToken = fields["access_token"]
	local tokenType = fields["token_type"]
	requestHeaders["Authorization"] = "" .. tokenType .. " " .. accessToken .. ""
	if (accessToken == "") then
		return LoginFailed
	end
	return nil
end

function EndSession ()
	local url = "https://www.deutschlandcard.de/logout"
	local content, charset, mimeType, filename, headers = connection:request("GET", url, nil, nil, requestHeaders)
	return nil
end

local function loadFile(filename)
	local file = assert(io.open("~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/" .. filename, "r"))
	local content = file:read("*all")
	file:close()
	return content
end

function ListAccounts (knownAccounts)
	local url = "https://www.deutschlandcard.de/api/v1/profile/memberinfo"
	local content, charset, mimeType, filename, headers = connection:request("GET", url, nil, nil, requestHeaders)
	local fields = JSON(content):dictionary()
	local account = {
		name = "Deutschlandcard Punkte",
		owner = fields["firstname"].." "..fields["lastname"],
		accountNumber = accountNumber,
		currency = "EUR",
		type = AccountTypeOther
	}
	return {account}
end


local function LoadTransactions(fromDate)
	local numMonths = 1
	local toDate = os.time();
	local fromYear = os.date('%Y', fromDate)
	local fromMonth = os.date('%m', fromDate)
	local toYear = os.date('%Y', toDate)
	local toMonth = os.date('%m', toDate)
	if(fromYear < toYear) then
		if(fromMonth > toMonth) then
			numMonths = numMonths + (12*(toYear-fromYear-1))
			numMonths = numMonths + (12-fromMonth)+toMonth
		elseif(fromMonth < toMonth) then
			numMonths = numMonths + (12*(toYear-fromYear))
			numMonths = numMonths + (toMonth-fromMonth)
		end
	else
		if(fromMonth > toMonth) then
			numMonths = numMonths
		elseif(fromMonth < toMonth) then
			numMonths = numMonths + (toMonth-fromMonth)
		end
	end
	local params = "Days=Default&Category=All&Limit="..numMonths
	local url = "https://www.deutschlandcard.de/api/v1/profile/bookings" .. "?" .. params
	local content, charset, mimeType, filename, headers = connection:request("GET", url, nil, nil, requestHeaders)
	return content
end


function RefreshAccount (account, since)
	-- Load Account Balance
	local url = "https://www.deutschlandcard.de/api/v1/profile/memberpoints"
	local content, charset, mimeType, filename, headers = connection:request("GET", url, nil, nil, requestHeaders)
	local fields = JSON(content):dictionary()
	local points = fields["balance"]
	local pointvalue = tonumber(points) / 100.0
	-- Load Transactions
	local json = LoadTransactions(since)
	local fields = JSON(json):dictionary()
	local transactions = {}
	for i,t in ipairs(fields["result"]) do
		items = t["bookings"]
		if (type(items) == "table") then
			for j, item in ipairs(items) do
				local transaction = {
					name = item["partner"],
					amount = (tonumber(item["amount"])/100),
					purpose = item["bookingText"],
					bookingDate = DatestringToPosixTime(item["transactionDate"]),
					valueDate = DatestringToPosixTime(item["transactionDate"])
				}
				table.insert(transactions, transaction)
			end
		end
	end
	return {balance=pointvalue, transactions=transactions}
end

-- for debugging purposes:
function tableToString(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. tableToString(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

import { WEBUI_BASE_URL } from '$lib/constants';

const getErrorDetail = (err: any) => {
	const detail = err?.detail ?? err?.message ?? err;
	if (typeof detail === 'string') {
		return detail || 'Tokenfun usage request failed';
	}
	if (detail && typeof detail === 'object' && 'detail' in detail) {
		return getErrorDetail(detail);
	}
	if (detail?.message) {
		return detail.message;
	}
	return detail ?? 'Tokenfun usage request failed';
};

const request = async (
	token: string,
	path: string,
	params: Record<string, string | number | null | undefined> = {}
) => {
	let error = null;
	const searchParams = new URLSearchParams();
	for (const [key, value] of Object.entries(params)) {
		if (value !== undefined && value !== null && value !== '') {
			searchParams.append(key, value.toString());
		}
	}

	const query = searchParams.toString();
	const res = await fetch(`${WEBUI_BASE_URL}${path}${query ? `?${query}` : ''}`, {
		method: 'GET',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			authorization: `Bearer ${token}`
		}
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorDetail(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const getTokenfunUsageSummary = async (
	token: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null
) =>
	request(token, '/api/usage/tokenfun/summary', {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp
	});

export const getTokenfunUsageChats = async (
	token: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null,
	page = 1,
	pageSize = 20
) =>
	request(token, '/api/usage/tokenfun/chats', {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp,
		p: page,
		page_size: pageSize
	});

export const getTokenfunUsageChatLogs = async (
	token: string,
	chatId: string,
	page = 1,
	pageSize = 20
) =>
	request(token, `/api/usage/tokenfun/chats/${encodeURIComponent(chatId)}/logs`, {
		p: page,
		page_size: pageSize
	});

export const getAdminTokenfunUsageUsers = async (
	token: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null,
	page = 1,
	pageSize = 20,
	externalUserId = '',
	externalUsername = ''
) =>
	request(token, '/api/admin/usage/tokenfun/users', {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp,
		p: page,
		page_size: pageSize,
		external_user_id: externalUserId,
		external_username: externalUsername
	});

export const getAdminTokenfunUsageModels = async (
	token: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null,
	page = 1,
	pageSize = 50
) =>
	request(token, '/api/admin/usage/tokenfun/models', {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp,
		p: page,
		page_size: pageSize
	});

export const getAdminTokenfunUsageSummary = async (
	token: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null
) =>
	request(token, '/api/admin/usage/tokenfun/summary', {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp
	});

export const getAdminTokenfunUsageUserChats = async (
	token: string,
	userId: string,
	startTimestamp?: number | null,
	endTimestamp?: number | null,
	page = 1,
	pageSize = 20
) =>
	request(token, `/api/admin/usage/tokenfun/users/${encodeURIComponent(userId)}/chats`, {
		start_timestamp: startTimestamp,
		end_timestamp: endTimestamp,
		p: page,
		page_size: pageSize
	});

export const getAdminTokenfunUsageChatLogs = async (
	token: string,
	chatId: string,
	externalUserId = '',
	page = 1,
	pageSize = 20
) =>
	request(token, `/api/admin/usage/tokenfun/chats/${encodeURIComponent(chatId)}/logs`, {
		external_user_id: externalUserId,
		p: page,
		page_size: pageSize
	});

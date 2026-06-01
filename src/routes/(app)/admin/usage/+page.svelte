<script lang="ts">
	import { onMount } from 'svelte';
	import {
		getAdminTokenfunUsageChatLogs,
		getAdminTokenfunUsageUserChats,
		getAdminTokenfunUsageUsers
	} from '$lib/apis/tokenfun-usage';

	let loading = true;
	let error = '';
	let users: any[] = [];
	let total = 0;
	let selectedUser: any = null;
	let chats: any[] = [];
	let selectedChat: any = null;
	let logs: any[] = [];
	let query = '';

	const formatNumber = (value: any) => Number(value ?? 0).toLocaleString();
	const formatCost = (item: any) => item?.cost_display ?? `$${Number(item?.cost_usd ?? 0).toFixed(6)}`;
	const formatTime = (value: any) => (value ? new Date(Number(value) * 1000).toLocaleString() : '-');

	const loadUsers = async () => {
		loading = true;
		error = '';
		selectedUser = null;
		selectedChat = null;
		chats = [];
		logs = [];
		try {
			const res = await getAdminTokenfunUsageUsers(
				localStorage.token,
				null,
				null,
				1,
				50,
				'',
				query
			);
			users = res?.data?.items ?? [];
			total = res?.data?.total ?? 0;
		} catch (err) {
			error = typeof err === 'string' ? err : JSON.stringify(err);
		} finally {
			loading = false;
		}
	};

	const openUser = async (item: any) => {
		selectedUser = item;
		selectedChat = null;
		logs = [];
		const res = await getAdminTokenfunUsageUserChats(localStorage.token, item.external_user_id, null, null, 1, 50);
		chats = res?.data?.items ?? [];
	};

	const openChat = async (item: any) => {
		selectedChat = item;
		const res = await getAdminTokenfunUsageChatLogs(
			localStorage.token,
			item.external_chat_id,
			item.external_user_id
		);
		logs = res?.data?.items ?? [];
	};

	onMount(loadUsers);
</script>

<div class="mx-auto w-full max-w-7xl px-4 py-6">
	<div class="mb-5 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
		<div>
			<h1 class="text-xl font-semibold text-gray-900 dark:text-gray-100">用量统计</h1>
			<div class="mt-1 text-sm text-gray-500">按 Open WebUI 用户归因查看 tokenfun 费用</div>
		</div>
		<div class="flex gap-2">
			<input
				class="w-56 rounded-lg border border-gray-200 bg-transparent px-3 py-1.5 text-sm outline-none focus:border-gray-400 dark:border-gray-800"
				placeholder="搜索用户名"
				bind:value={query}
				on:keydown={(event) => {
					if (event.key === 'Enter') loadUsers();
				}}
			/>
			<button
				class="rounded-lg border border-gray-200 px-3 py-1.5 text-sm hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900"
				on:click={loadUsers}
			>
				查询
			</button>
		</div>
	</div>

	{#if error}
		<div class="mb-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-200">
			{error}
		</div>
	{/if}

	<div class="grid grid-cols-1 gap-4 xl:grid-cols-[minmax(0,1fr)_minmax(360px,0.8fr)]">
		<div class="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800">
			<div class="flex items-center justify-between border-b border-gray-200 px-4 py-3 dark:border-gray-800">
				<div class="font-medium">用户排行</div>
				<div class="text-sm text-gray-500">{formatNumber(total)} 个用户</div>
			</div>
			{#if loading}
				<div class="py-12 text-center text-sm text-gray-500">加载中...</div>
			{:else}
				<div class="overflow-x-auto">
					<table class="w-full text-left text-sm">
						<thead class="bg-gray-50 text-xs text-gray-500 dark:bg-gray-900">
							<tr>
								<th class="px-4 py-2">用户</th>
								<th class="px-4 py-2">邮箱</th>
								<th class="px-4 py-2">请求数</th>
								<th class="px-4 py-2">总 tokens</th>
								<th class="px-4 py-2">花费</th>
								<th class="px-4 py-2">最近使用</th>
							</tr>
						</thead>
						<tbody>
							{#each users as item}
								<tr class="border-t border-gray-100 hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900">
									<td class="px-4 py-2">
										<button class="text-left text-blue-600 dark:text-blue-400" on:click={() => openUser(item)}>
											<div class="max-w-48 truncate">{item.external_username || item.external_user_id}</div>
											<div class="max-w-48 truncate text-xs text-gray-500">{item.external_user_id}</div>
										</button>
									</td>
									<td class="px-4 py-2">{item.external_user_email || '-'}</td>
									<td class="px-4 py-2">{formatNumber(item.request_count)}</td>
									<td class="px-4 py-2">{formatNumber(item.total_tokens)}</td>
									<td class="px-4 py-2">{formatCost(item)}</td>
									<td class="px-4 py-2">{formatTime(item.last_seen_at)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</div>

		<div class="space-y-4">
			<div class="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800">
				<div class="border-b border-gray-200 px-4 py-3 dark:border-gray-800">
					<div class="font-medium">会话</div>
					<div class="mt-1 text-xs text-gray-500">{selectedUser?.external_username || '选择左侧用户'}</div>
				</div>
				<div class="max-h-80 overflow-y-auto">
					{#each chats as chat}
						<button
							class="flex w-full items-center justify-between gap-3 border-t border-gray-100 px-4 py-3 text-left text-sm hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900"
							on:click={() => openChat(chat)}
						>
							<span class="min-w-0">
								<span class="block truncate">{chat.external_chat_id}</span>
								<span class="text-xs text-gray-500">{formatTime(chat.last_seen_at)}</span>
							</span>
							<span class="shrink-0 text-gray-600 dark:text-gray-300">{formatCost(chat)}</span>
						</button>
					{/each}
					{#if selectedUser && chats.length === 0}
						<div class="px-4 py-8 text-center text-sm text-gray-500">暂无会话用量</div>
					{/if}
				</div>
			</div>

			<div class="overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800">
				<div class="border-b border-gray-200 px-4 py-3 dark:border-gray-800">
					<div class="font-medium">请求明细</div>
					<div class="mt-1 text-xs text-gray-500">{selectedChat?.external_chat_id || '选择会话'}</div>
				</div>
				<div class="max-h-96 overflow-y-auto">
					{#each logs as log}
						<div class="border-t border-gray-100 px-4 py-3 text-sm dark:border-gray-800">
							<div class="flex items-center justify-between gap-3">
								<div class="min-w-0 truncate">{log.model_name || '-'}</div>
								<div class="shrink-0 font-medium">{formatCost(log)}</div>
							</div>
							<div class="mt-1 text-xs text-gray-500">
								{formatTime(log.created_at)} · 输入 {formatNumber(log.prompt_tokens)} · 输出 {formatNumber(log.completion_tokens)}
							</div>
							<div class="mt-1 truncate text-xs text-gray-500">{log.external_message_id || '-'}</div>
						</div>
					{/each}
					{#if selectedChat && logs.length === 0}
						<div class="px-4 py-8 text-center text-sm text-gray-500">暂无请求明细</div>
					{/if}
				</div>
			</div>
		</div>
	</div>
</div>

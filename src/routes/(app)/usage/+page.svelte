<script lang="ts">
	import { onMount } from 'svelte';
	import { WEBUI_NAME } from '$lib/stores';
	import {
		getTokenfunUsageChatLogs,
		getTokenfunUsageChats,
		getTokenfunUsageSummary
	} from '$lib/apis/tokenfun-usage';

	let loading = true;
	let error = '';
	let summary: any = null;
	let chats: any[] = [];
	let total = 0;
	let selectedChat: any = null;
	let logs: any[] = [];
	let logsTotal = 0;

	const formatNumber = (value: any) => Number(value ?? 0).toLocaleString();
	const formatCost = (item: any) => item?.cost_display ?? `$${Number(item?.cost_usd ?? 0).toFixed(6)}`;
	const formatTime = (value: any) => (value ? new Date(Number(value) * 1000).toLocaleString() : '-');

	const load = async () => {
		loading = true;
		error = '';
		try {
			const [summaryRes, chatsRes] = await Promise.all([
				getTokenfunUsageSummary(localStorage.token),
				getTokenfunUsageChats(localStorage.token)
			]);
			summary = summaryRes?.data ?? {};
			chats = chatsRes?.data?.items ?? [];
			total = chatsRes?.data?.total ?? 0;
		} catch (err) {
			error = typeof err === 'string' ? err : JSON.stringify(err);
		} finally {
			loading = false;
		}
	};

	const openChat = async (chat: any) => {
		selectedChat = chat;
		logs = [];
		logsTotal = 0;
		try {
			const res = await getTokenfunUsageChatLogs(localStorage.token, chat.external_chat_id);
			logs = res?.data?.items ?? [];
			logsTotal = res?.data?.total ?? 0;
		} catch (err) {
			error = typeof err === 'string' ? err : JSON.stringify(err);
		}
	};

	onMount(load);
</script>

<svelte:head>
	<title>用量统计 • {$WEBUI_NAME}</title>
</svelte:head>

<div class="h-full overflow-y-auto">
	<div class="mx-auto w-full max-w-6xl px-4 py-6">
		<div class="mb-5 flex items-center justify-between gap-3">
			<div>
				<h1 class="text-xl font-semibold text-gray-900 dark:text-gray-100">用量统计</h1>
				<div class="mt-1 text-sm text-gray-500">按 tokenfun 最终结算日志统计</div>
			</div>
			<button
				class="rounded-lg border border-gray-200 px-3 py-1.5 text-sm hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900"
				on:click={load}
			>
				刷新
			</button>
		</div>

		{#if error}
			<div class="mb-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-200">
				{error}
			</div>
		{/if}

		{#if loading}
			<div class="py-12 text-center text-sm text-gray-500">加载中...</div>
		{:else}
			<div class="grid grid-cols-2 gap-3 md:grid-cols-4">
				<div class="rounded-lg border border-gray-200 p-4 dark:border-gray-800">
					<div class="text-xs text-gray-500">请求数</div>
					<div class="mt-2 text-2xl font-semibold">{formatNumber(summary?.request_count)}</div>
				</div>
				<div class="rounded-lg border border-gray-200 p-4 dark:border-gray-800">
					<div class="text-xs text-gray-500">输入 tokens</div>
					<div class="mt-2 text-2xl font-semibold">{formatNumber(summary?.prompt_tokens)}</div>
				</div>
				<div class="rounded-lg border border-gray-200 p-4 dark:border-gray-800">
					<div class="text-xs text-gray-500">输出 tokens</div>
					<div class="mt-2 text-2xl font-semibold">{formatNumber(summary?.completion_tokens)}</div>
				</div>
				<div class="rounded-lg border border-gray-200 p-4 dark:border-gray-800">
					<div class="text-xs text-gray-500">花费</div>
					<div class="mt-2 text-2xl font-semibold">{formatCost(summary)}</div>
				</div>
			</div>

			<div class="mt-6 overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800">
				<div class="flex items-center justify-between border-b border-gray-200 px-4 py-3 dark:border-gray-800">
					<div class="font-medium">会话用量</div>
					<div class="text-sm text-gray-500">{formatNumber(total)} 个会话</div>
				</div>
				<div class="overflow-x-auto">
					<table class="w-full text-left text-sm">
						<thead class="bg-gray-50 text-xs text-gray-500 dark:bg-gray-900">
							<tr>
								<th class="px-4 py-2">会话 ID</th>
								<th class="px-4 py-2">请求数</th>
								<th class="px-4 py-2">总 tokens</th>
								<th class="px-4 py-2">花费</th>
								<th class="px-4 py-2">最近使用</th>
							</tr>
						</thead>
						<tbody>
							{#each chats as chat}
								<tr class="border-t border-gray-100 hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-900">
									<td class="px-4 py-2">
										<button class="max-w-xs truncate text-left text-blue-600 dark:text-blue-400" on:click={() => openChat(chat)}>
											{chat.external_chat_id}
										</button>
									</td>
									<td class="px-4 py-2">{formatNumber(chat.request_count)}</td>
									<td class="px-4 py-2">{formatNumber(chat.total_tokens)}</td>
									<td class="px-4 py-2">{formatCost(chat)}</td>
									<td class="px-4 py-2">{formatTime(chat.last_seen_at)}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>

			{#if selectedChat}
				<div class="mt-6 overflow-hidden rounded-lg border border-gray-200 dark:border-gray-800">
					<div class="border-b border-gray-200 px-4 py-3 dark:border-gray-800">
						<div class="font-medium">请求明细</div>
						<div class="mt-1 text-xs text-gray-500">{selectedChat.external_chat_id} · {formatNumber(logsTotal)} 条</div>
					</div>
					<div class="overflow-x-auto">
						<table class="w-full text-left text-sm">
							<thead class="bg-gray-50 text-xs text-gray-500 dark:bg-gray-900">
								<tr>
									<th class="px-4 py-2">时间</th>
									<th class="px-4 py-2">模型</th>
									<th class="px-4 py-2">消息 ID</th>
									<th class="px-4 py-2">输入</th>
									<th class="px-4 py-2">输出</th>
									<th class="px-4 py-2">花费</th>
									<th class="px-4 py-2">耗时</th>
								</tr>
							</thead>
							<tbody>
								{#each logs as log}
									<tr class="border-t border-gray-100 dark:border-gray-800">
										<td class="px-4 py-2">{formatTime(log.created_at)}</td>
										<td class="px-4 py-2">{log.model_name || '-'}</td>
										<td class="px-4 py-2"><span class="block max-w-xs truncate">{log.external_message_id || '-'}</span></td>
										<td class="px-4 py-2">{formatNumber(log.prompt_tokens)}</td>
										<td class="px-4 py-2">{formatNumber(log.completion_tokens)}</td>
										<td class="px-4 py-2">{formatCost(log)}</td>
										<td class="px-4 py-2">{formatNumber(log.use_time)}s</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
				</div>
			{/if}
		{/if}
	</div>
</div>

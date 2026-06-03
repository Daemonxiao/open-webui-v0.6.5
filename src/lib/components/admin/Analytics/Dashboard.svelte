<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { models } from '$lib/stores';
	import {
		getAdminTokenfunUsageModels,
		getAdminTokenfunUsageSummary,
		getAdminTokenfunUsageUsers
	} from '$lib/apis/tokenfun-usage';
	import Spinner from '$lib/components/common/Spinner.svelte';
	import ChevronUp from '$lib/components/icons/ChevronUp.svelte';
	import ChevronDown from '$lib/components/icons/ChevronDown.svelte';
	import { WEBUI_API_BASE_URL } from '$lib/constants';
	import { decodeString, formatNumber } from '$lib/utils';

	const maxRangeDays = 31;
	const daySeconds = 86400;
	const toDateInput = (date: Date) => {
		const year = date.getFullYear();
		const month = `${date.getMonth() + 1}`.padStart(2, '0');
		const day = `${date.getDate()}`.padStart(2, '0');
		return `${year}-${month}-${day}`;
	};
	const today = toDateInput(new Date());
	const defaultStartDate = toDateInput(new Date(Date.now() - 6 * daySeconds * 1000));
	const startDateStorageKey = 'analyticsStartDateLocal';
	const endDateStorageKey = 'analyticsEndDateLocal';
	const analyticsCostVisibilityStorageKey = 'analyticsShowCosts';

	let startDate =
		typeof localStorage !== 'undefined'
			? (localStorage.getItem(startDateStorageKey) ?? defaultStartDate)
			: defaultStartDate;
	let endDate =
		typeof localStorage !== 'undefined'
			? (localStorage.getItem(endDateStorageKey) ?? today)
			: today;

	let summary = {
		request_count: 0,
		total_tokens: 0,
		prompt_tokens: 0,
		completion_tokens: 0,
		cost_usd: 0,
		cost_display: '$0.000000'
	};
	let modelStats: Array<any> = [];
	let userStats: Array<any> = [];
	let loading = true;
	let tokenfunError = '';
	let showAnalyticsCosts =
		typeof localStorage !== 'undefined'
			? localStorage.getItem(analyticsCostVisibilityStorageKey) === 'true'
			: false;

	let modelOrderBy = 'count';
	let modelDirection: 'asc' | 'desc' = 'desc';
	let userOrderBy = 'requests';
	let userDirection: 'asc' | 'desc' = 'desc';

	const parseDate = (value: string) => {
		const [year, month, day] = value.split('-').map((part) => Number(part));
		if (!year || !month || !day) {
			return null;
		}
		return new Date(year, month - 1, day);
	};

	const clampDateRange = () => {
		let start = parseDate(startDate) ?? new Date(Date.now() - 6 * daySeconds * 1000);
		let end = parseDate(endDate) ?? new Date();

		if (start > end) {
			start = new Date(end);
		}

		const maxStart = new Date(end.getTime() - (maxRangeDays - 1) * daySeconds * 1000);
		if (start < maxStart) {
			start = maxStart;
		}

		startDate = toDateInput(start);
		endDate = toDateInput(end);
	};

	const getDateRange = () => {
		clampDateRange();
		const start = parseDate(startDate);
		const end = parseDate(endDate);
		const startTimestamp = Math.floor((start ?? new Date()).getTime() / 1000);
		const endDateTime = end ?? new Date();
		endDateTime.setHours(23, 59, 59, 999);
		const endTimestamp = Math.floor(endDateTime.getTime() / 1000);
		return { start: startTimestamp, end: endTimestamp };
	};

	const formatCost = (item: any) =>
		item?.cost_display ?? `$${Number(item?.cost_usd ?? 0).toFixed(6)}`;

	const loadCostVisibility = () => {
		showAnalyticsCosts =
			typeof localStorage !== 'undefined'
				? localStorage.getItem(analyticsCostVisibilityStorageKey) === 'true'
				: false;
		if (!showAnalyticsCosts && userOrderBy === 'cost') {
			userOrderBy = 'requests';
		}
	};

	const compareNumber = (a: number, b: number, direction: 'asc' | 'desc') =>
		direction === 'asc' ? a - b : b - a;

	const toggleModelSort = (key: string) => {
		if (modelOrderBy === key) {
			modelDirection = modelDirection === 'asc' ? 'desc' : 'asc';
		} else {
			modelOrderBy = key;
			modelDirection = key === 'name' ? 'asc' : 'desc';
		}
	};

	const toggleUserSort = (key: string) => {
		if (userOrderBy === key) {
			userDirection = userDirection === 'asc' ? 'desc' : 'asc';
		} else {
			userOrderBy = key;
			userDirection = key === 'name' ? 'asc' : 'desc';
		}
	};

	const loadDashboard = async () => {
		loading = true;
		tokenfunError = '';
		try {
			const { start, end } = getDateRange();
			if (typeof localStorage !== 'undefined') {
				localStorage.setItem(startDateStorageKey, startDate);
				localStorage.setItem(endDateStorageKey, endDate);
			}

			const modelsMap = new Map($models.map((m) => [m.id, m.name || m.id]));
			const [summaryRes, modelsRes, usersRes] = await Promise.all([
				getAdminTokenfunUsageSummary(localStorage.token, start, end),
				getAdminTokenfunUsageModels(localStorage.token, start, end, 1, 50),
				getAdminTokenfunUsageUsers(localStorage.token, start, end, 1, 50)
			]);
			summary = summaryRes?.data ?? summary;
			modelStats = (modelsRes?.data?.items ?? []).map((entry: any) => ({
				...entry,
				name: modelsMap.get(entry.model_name) || entry.model_name
			}));
			userStats = (usersRes?.data?.items ?? []).map((entry: any) => ({
				...entry,
				_display_username: entry.external_username ? decodeString(entry.external_username) : '',
				_display_user_email: entry.external_user_email
					? decodeString(entry.external_user_email)
					: ''
			}));
		} catch (err) {
			tokenfunError = typeof err === 'string' ? err : JSON.stringify(err);
			summary = {
				request_count: 0,
				total_tokens: 0,
				prompt_tokens: 0,
				completion_tokens: 0,
				cost_usd: 0,
				cost_display: '$0.000000'
			};
			modelStats = [];
			userStats = [];
		} finally {
			loading = false;
		}
	};

	$: sortedModels = [...modelStats].sort((a, b) => {
		if (modelOrderBy === 'name') {
			const nameA = a.name || a.model_name;
			const nameB = b.name || b.model_name;
			return modelDirection === 'asc' ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
		}
		if (modelOrderBy === 'tokens') {
			return compareNumber(
				Number(a.total_tokens ?? 0),
				Number(b.total_tokens ?? 0),
				modelDirection
			);
		}
		return compareNumber(
			Number(a.request_count ?? 0),
			Number(b.request_count ?? 0),
			modelDirection
		);
	});

	$: sortedUsers = [...userStats].sort((a, b) => {
		if (userOrderBy === 'name') {
			const nameA = a._display_username || a._display_user_email || a.external_user_id || '';
			const nameB = b._display_username || b._display_user_email || b.external_user_id || '';
			return userDirection === 'asc' ? nameA.localeCompare(nameB) : nameB.localeCompare(nameA);
		}
		if (userOrderBy === 'tokens') {
			return compareNumber(Number(a.total_tokens ?? 0), Number(b.total_tokens ?? 0), userDirection);
		}
		if (userOrderBy === 'requests') {
			return compareNumber(
				Number(a.request_count ?? 0),
				Number(b.request_count ?? 0),
				userDirection
			);
		}
		return compareNumber(Number(a.cost_usd ?? 0), Number(b.cost_usd ?? 0), userDirection);
	});

	onMount(() => {
		loadCostVisibility();
		window.addEventListener('analytics-cost-visibility-change', loadCostVisibility);
		loadDashboard();
	});

	onDestroy(() => {
		window.removeEventListener('analytics-cost-visibility-change', loadCostVisibility);
	});
</script>

<div
	class="pt-0.5 pb-2 gap-2 flex flex-col md:flex-row md:justify-between md:items-center sticky top-0 z-10 bg-white dark:bg-gray-900"
>
	<div>
		<div class="text-lg font-medium px-0.5 shrink-0">分析</div>
	</div>
	<div class="flex items-center gap-2 flex-wrap justify-end min-w-0">
		<input
			type="date"
			bind:value={startDate}
			max={endDate}
			class="rounded-sm border border-gray-200 bg-transparent px-2 py-1 text-xs outline-none dark:border-gray-800"
			aria-label="开始日期"
			on:change={loadDashboard}
		/>
		<span class="text-xs text-gray-400">至</span>
		<input
			type="date"
			bind:value={endDate}
			min={startDate}
			class="rounded-sm border border-gray-200 bg-transparent px-2 py-1 text-xs outline-none dark:border-gray-800"
			aria-label="结束日期"
			on:change={loadDashboard}
		/>
		<button
			class="rounded-sm border border-gray-200 px-2 py-1 text-xs hover:bg-gray-50 dark:border-gray-800 dark:hover:bg-gray-850"
			on:click={loadDashboard}
		>
			刷新
		</button>
	</div>
</div>

{#if tokenfunError}
	<div
		class="mb-3 rounded-md border border-yellow-200 bg-yellow-50 px-3 py-2 text-xs text-yellow-800 dark:border-yellow-900 dark:bg-yellow-950 dark:text-yellow-100"
	>
		tokenfun 用量暂不可用：{tokenfunError}
	</div>
{/if}

{#if loading}
	<div class="my-10 flex justify-center">
		<Spinner className="size-5" />
	</div>
{:else}
	<div class="flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400 px-0.5 pb-3">
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.request_count)}</span
			>
			API请求
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.total_tokens)}</span
			>
			tokens
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.prompt_tokens)}</span
			>
			输入
		</span>
		<span>
			<span class="font-medium text-gray-900 dark:text-gray-300"
				>{formatNumber(summary.completion_tokens)}</span
			>
			输出
		</span>
		{#if showAnalyticsCosts}
			<span>
				<span class="font-medium text-gray-900 dark:text-gray-300">{formatCost(summary)}</span>
				费用
			</span>
		{/if}
	</div>

	<div class="grid md:grid-cols-2 gap-4">
		<div>
			<div class="text-xs font-medium text-gray-700 dark:text-gray-300 mb-1 px-0.5">模型用量</div>
			<div class="scrollbar-hidden relative whitespace-nowrap overflow-x-auto max-w-full">
				<table class="w-full text-sm text-left text-gray-500 dark:text-gray-400 table-auto">
					<thead class="text-xs text-gray-800 uppercase bg-transparent dark:text-gray-200">
						<tr class="border-b-[1.5px] border-gray-50 dark:border-gray-850/30">
							<th scope="col" class="px-2.5 py-2 w-8">#</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none"
								on:click={() => toggleModelSort('name')}
							>
								<div class="flex gap-1.5 items-center">
									模型
									{#if modelOrderBy === 'name'}
										{#if modelDirection === 'asc'}<ChevronUp
												className="size-2"
											/>{:else}<ChevronDown className="size-2" />{/if}
									{:else}
										<span class="invisible"><ChevronUp className="size-2" /></span>
									{/if}
								</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleModelSort('count')}
							>
								<div class="flex gap-1.5 items-center justify-end">API请求</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleModelSort('tokens')}
							>
								<div class="flex gap-1.5 items-center justify-end">Tokens</div>
							</th>
						</tr>
					</thead>
					<tbody>
						{#each sortedModels as model, idx (model.model_name)}
							<tr class="bg-white dark:bg-gray-900 dark:border-gray-850 text-xs">
								<td class="px-3 py-1 text-gray-400">{idx + 1}</td>
								<td class="px-3 py-1 font-medium text-gray-900 dark:text-white">
									<div class="flex items-center gap-2">
										<img
											src="{WEBUI_API_BASE_URL}/models/model/profile/image?id={model.model_name}"
											alt={model.name}
											class="size-5 rounded-full object-cover shrink-0"
											on:error={(e) => {
												(e.currentTarget as HTMLImageElement).src = '/favicon.png';
											}}
										/>
										<span class="truncate max-w-[180px]">{model.name}</span>
									</div>
								</td>
								<td class="px-3 py-1 text-right">{formatNumber(model.request_count)}</td>
								<td class="px-3 py-1 text-right">{formatNumber(model.total_tokens)}</td>
							</tr>
						{/each}
						{#if sortedModels.length === 0}
							<tr><td colspan="4" class="px-3 py-2 text-center text-gray-400">暂无数据</td></tr>
						{/if}
					</tbody>
				</table>
			</div>
		</div>

		<div>
			<div class="text-xs font-medium text-gray-700 dark:text-gray-300 mb-1 px-0.5">用户动态</div>
			<div class="scrollbar-hidden relative whitespace-nowrap overflow-x-auto max-w-full">
				<table class="w-full text-sm text-left text-gray-500 dark:text-gray-400 table-auto">
					<thead class="text-xs text-gray-800 uppercase bg-transparent dark:text-gray-200">
						<tr class="border-b-[1.5px] border-gray-50 dark:border-gray-850/30">
							<th scope="col" class="px-2.5 py-2 w-8">#</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none"
								on:click={() => toggleUserSort('name')}
							>
								<div class="flex gap-1.5 items-center">
									用户
									{#if userOrderBy === 'name'}
										{#if userDirection === 'asc'}<ChevronUp className="size-2" />{:else}<ChevronDown
												className="size-2"
											/>{/if}
									{:else}
										<span class="invisible"><ChevronUp className="size-2" /></span>
									{/if}
								</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleUserSort('requests')}
							>
								<div class="flex gap-1.5 items-center justify-end">API请求</div>
							</th>
							<th
								scope="col"
								class="px-2.5 py-2 cursor-pointer select-none text-right"
								on:click={() => toggleUserSort('tokens')}
							>
								<div class="flex gap-1.5 items-center justify-end">Tokens</div>
							</th>
							{#if showAnalyticsCosts}
								<th
									scope="col"
									class="px-2.5 py-2 cursor-pointer select-none text-right"
									on:click={() => toggleUserSort('cost')}
								>
									<div class="flex gap-1.5 items-center justify-end">费用</div>
								</th>
							{/if}
						</tr>
					</thead>
					<tbody>
						{#each sortedUsers as item, idx (item.external_user_id)}
							<tr class="bg-white dark:bg-gray-900 dark:border-gray-850 text-xs">
								<td class="px-3 py-1 text-gray-400">{idx + 1}</td>
								<td class="px-3 py-1 font-medium text-gray-900 dark:text-white">
									<div class="flex items-center gap-2">
										<img
											src="{WEBUI_API_BASE_URL}/users/{item.external_user_id}/profile/image"
											alt={item._display_username || 'User'}
											class="size-5 rounded-full object-cover shrink-0"
											on:error={(e) => {
												(e.currentTarget as HTMLImageElement).src = '/user.png';
											}}
										/>
										<span class="min-w-0">
											<span class="block truncate max-w-[160px]"
												>{item._display_username ||
													item._display_user_email ||
													item.external_user_id}</span
											>
											{#if item._display_user_email}
												<span class="block truncate max-w-[160px] text-[11px] text-gray-400"
													>{item._display_user_email}</span
												>
											{/if}
										</span>
									</div>
								</td>
								<td class="px-3 py-1 text-right">{formatNumber(item.request_count)}</td>
								<td class="px-3 py-1 text-right">{formatNumber(item.total_tokens)}</td>
								{#if showAnalyticsCosts}
									<td class="px-3 py-1 text-right">{formatCost(item)}</td>
								{/if}
							</tr>
						{/each}
						{#if sortedUsers.length === 0}
							<tr
								><td
									colspan={showAnalyticsCosts ? 5 : 4}
									class="px-3 py-2 text-center text-gray-400">暂无数据</td
								></tr
							>
						{/if}
					</tbody>
				</table>
			</div>
		</div>
	</div>
{/if}

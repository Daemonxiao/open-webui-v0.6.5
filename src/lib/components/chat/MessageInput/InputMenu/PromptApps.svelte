<script lang="ts">
	import { getContext, onMount } from 'svelte';
	import { getPromptApps } from '$lib/apis/prompts';
	import Spinner from '$lib/components/common/Spinner.svelte';
	import Search from '$lib/components/icons/Search.svelte';
	import XMark from '$lib/components/icons/XMark.svelte';
	import Tooltip from '$lib/components/common/Tooltip.svelte';

	const i18n: any = getContext('i18n');

	export let onSelect: Function = () => {};

	let loading = true;
	let promptApps: any[] = [];
	let query = '';

	$: filteredPromptApps = promptApps.filter((promptApp) => {
		const normalizedQuery = query.trim().toLowerCase();
		if (!normalizedQuery) return true;
		return (promptApp.name ?? '').toLowerCase().includes(normalizedQuery);
	});

	onMount(async () => {
		const res = await getPromptApps(localStorage.token).catch((error) => {
			console.error(error);
			return null;
		});

		promptApps = res?.items ?? [];
		loading = false;
	});
</script>

<div class="px-2 pb-2">
	<div
		class="flex items-center gap-2 rounded-xl bg-gray-50 px-2.5 py-1.5 dark:bg-gray-800/50"
	>
		<Search className="size-3.5 shrink-0 text-gray-500" />
		<input
			class="w-full bg-transparent text-sm outline-hidden placeholder:text-gray-400"
			bind:value={query}
			placeholder={$i18n.t('Search Prompt Apps')}
			aria-label={$i18n.t('Search Prompt Apps')}
		/>
		{#if query}
			<button
				type="button"
				class="rounded-full p-0.5 hover:bg-black/5 dark:hover:bg-white/10"
				aria-label={$i18n.t('Clear search')}
				on:click={() => {
					query = '';
				}}
			>
				<XMark className="size-3.5" strokeWidth="2" />
			</button>
		{/if}
	</div>
</div>

{#if loading}
	<div class="flex justify-center py-3">
		<Spinner className="size-4" />
	</div>
{:else if filteredPromptApps.length > 0}
	<div class="flex flex-col gap-0.5">
		{#each filteredPromptApps as promptApp (promptApp.id)}
			<button
				class="text-left px-3 py-2.5 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-800/50 transition"
				type="button"
				on:click={() => onSelect(promptApp)}
			>
				<div class="text-sm font-medium line-clamp-1">{promptApp.name}</div>
				{#if promptApp.description}
					<Tooltip
						content={promptApp.description}
						placement="right"
						tippyOptions={{ maxWidth: 360, delay: [300, 0] }}
					>
						<div class="text-xs leading-5 text-gray-500 line-clamp-3 mt-1">
							{promptApp.description}
						</div>
					</Tooltip>
				{/if}
			</button>
		{/each}
	</div>
{:else}
	<div class="px-3 py-2 text-sm text-gray-500">
		{query ? $i18n.t('No prompt apps found') : $i18n.t('No prompts found')}
	</div>
{/if}

<script lang="ts">
	import { toast } from 'svelte-sonner';

	import { onMount, getContext, tick, onDestroy } from 'svelte';
	import { WEBUI_NAME, user } from '$lib/stores';

	import {
		createNewPrompt,
		deletePromptById,
		getPromptById,
		togglePromptById,
		getPromptItems,
		getPromptTags,
		updatePromptById
	} from '$lib/apis/prompts';
	import { capitalizeFirstLetter, slugify } from '$lib/utils';

	import PromptMenu from './Prompts/PromptMenu.svelte';
	import EllipsisHorizontal from '../icons/EllipsisHorizontal.svelte';
	import DeleteConfirmDialog from '$lib/components/common/ConfirmDialog.svelte';
	import Search from '../icons/Search.svelte';
	import Plus from '../icons/Plus.svelte';
	import Spinner from '../common/Spinner.svelte';
	import Tooltip from '../common/Tooltip.svelte';
	import XMark from '../icons/XMark.svelte';
	import GarbageBin from '../icons/GarbageBin.svelte';
	import ViewSelector from './common/ViewSelector.svelte';
	import TagSelector from './common/TagSelector.svelte';
	import Badge from '$lib/components/common/Badge.svelte';
	import Switch from '../common/Switch.svelte';
	import Pagination from '../common/Pagination.svelte';
	import Drawer from '../common/Drawer.svelte';
	import PromptEditor from './Prompts/PromptEditor.svelte';

	let shiftKey = false;

	const i18n = getContext('i18n');
	let loaded = false;

	let query = '';
	let searchDebounceTimer: ReturnType<typeof setTimeout>;

	let prompts = null;
	let tags = [];
	let total = null;
	let loading = false;

	let showDeleteConfirm = false;
	let deletePrompt = null;
	let showCreateDrawer = false;
	let createPromptSeed = null;
	let clonePrompt = false;
	let editPrompt = false;
	let drawerDisabled = false;

	let tagsContainerElement: HTMLDivElement;
	let viewOption = '';
	let selectedTag = '';

	let page = 1;

	// Debounce only query changes
	$: if (query !== undefined) {
		loading = true;
		clearTimeout(searchDebounceTimer);
		searchDebounceTimer = setTimeout(() => {
			page = 1;
			getPromptList();
		}, 300);
	}

	// Immediate response to page/filter changes
	$: if (page && selectedTag !== undefined && viewOption !== undefined) {
		getPromptList();
	}

	const getPromptList = async () => {
		if (!loaded) return;

		loading = true;
		try {
			const res = await getPromptItems(
				localStorage.token,
				query,
				viewOption,
				selectedTag,
				'created_at',
				'desc',
				page
			).catch((error) => {
				toast.error(`${error}`);
				return null;
			});

			if (res) {
				prompts = res.items;
				total = res.total;

				// get tags
				tags = await getPromptTags(localStorage.token).catch((error) => {
					toast.error(`${error}`);
					return [];
				});
			}
		} catch (err) {
			console.error(err);
		} finally {
			loading = false;
		}
	};

	const cloneHandler = async (prompt) => {
		const clonedPrompt = { ...prompt };

		clonedPrompt.name = `${clonedPrompt.name} (Clone)`;
		const baseCommand = clonedPrompt.command.startsWith('/')
			? clonedPrompt.command.substring(1)
			: clonedPrompt.command;
		clonedPrompt.command = slugify(`${baseCommand} clone`);

		createPromptSeed = clonedPrompt;
		clonePrompt = true;
		editPrompt = false;
		drawerDisabled = false;
		showCreateDrawer = true;
	};

	const openEditDrawer = async (prompt) => {
		const fullPrompt = await getPromptById(localStorage.token, prompt.id).catch((error) => {
			toast.error(`${error}`);
			return null;
		});

		if (!fullPrompt) return;

		createPromptSeed = {
			id: fullPrompt.id,
			name: fullPrompt.name,
			command: fullPrompt.command,
			description: fullPrompt.description ?? '',
			content: fullPrompt.content,
			version_id: fullPrompt.version_id,
			tags: fullPrompt.tags ?? [],
			access_grants: fullPrompt.access_grants ?? []
		};
		clonePrompt = false;
		editPrompt = true;
		drawerDisabled = !(fullPrompt.write_access ?? false);
		showCreateDrawer = true;
	};

	const createPromptHandler = async (_prompt) => {
		const res = await createNewPrompt(localStorage.token, _prompt).catch((error) => {
			toast.error(`${error}`);
			return null;
		});

		if (res) {
			toast.success($i18n.t('Prompt created successfully'));
			showCreateDrawer = false;
			createPromptSeed = null;
			clonePrompt = false;
			page = 1;
			await getPromptList();
		}
	};

	const updatePromptHandler = async (_prompt) => {
		const res = await updatePromptById(localStorage.token, _prompt).catch((error) => {
			toast.error(`${error}`);
			return null;
		});

		if (res) {
			toast.success($i18n.t('Prompt updated successfully'));
			showCreateDrawer = false;
			createPromptSeed = null;
			clonePrompt = false;
			editPrompt = false;
			drawerDisabled = false;
			await getPromptList();
		}
	};

	const deleteHandler = async (prompt) => {
		const command = prompt.command;

		const res = await deletePromptById(localStorage.token, prompt.id).catch((err) => {
			toast.error(err);
			return null;
		});

		if (res) {
			toast.success($i18n.t(`Deleted {{name}}`, { name: command }));
		}

		page = 1;
		getPromptList();
	};

	onMount(async () => {
		viewOption = localStorage?.workspaceViewOption || '';
		if (viewOption === 'shared') {
			viewOption = '';
			localStorage.workspaceViewOption = '';
		}
		loaded = true;

		const onKeyDown = (event) => {
			if (event.key === 'Shift') {
				shiftKey = true;
			}
		};

		const onKeyUp = (event) => {
			if (event.key === 'Shift') {
				shiftKey = false;
			}
		};

		const onBlur = () => {
			shiftKey = false;
		};

		window.addEventListener('keydown', onKeyDown);
		window.addEventListener('keyup', onKeyUp);
		window.addEventListener('blur', onBlur);

		return () => {
			clearTimeout(searchDebounceTimer);
			window.removeEventListener('keydown', onKeyDown);
			window.removeEventListener('keyup', onKeyUp);
			window.removeEventListener('blur', onBlur);
		};
	});

	onDestroy(() => {
		clearTimeout(searchDebounceTimer);
	});
</script>

<svelte:head>
	<title>
		{$i18n.t('Prompt Apps')} • {$WEBUI_NAME}
	</title>
</svelte:head>

{#if loaded}
	<DeleteConfirmDialog
		bind:show={showDeleteConfirm}
		title={$i18n.t('Delete prompt app?')}
		on:confirm={() => {
			deleteHandler(deletePrompt);
		}}
	>
		<div class=" text-sm text-gray-500 truncate">
			{$i18n.t('This will delete')} <span class="  font-medium">{deletePrompt.command}</span>.
		</div>
	</DeleteConfirmDialog>

	<Drawer
		bind:show={showCreateDrawer}
		side="right"
		className="w-full max-w-4xl !bg-gray-50 dark:!bg-gray-950"
		onClose={() => {
			createPromptSeed = null;
			clonePrompt = false;
			editPrompt = false;
			drawerDisabled = false;
		}}
	>
		<div class="min-h-full px-4 md:px-6">
			{#key `${editPrompt ? 'edit' : 'create'}-${createPromptSeed?.id ?? createPromptSeed?.command ?? ''}`}
				<PromptEditor
					prompt={createPromptSeed}
					onSubmit={editPrompt ? updatePromptHandler : createPromptHandler}
					clone={clonePrompt}
					edit={editPrompt}
					disabled={drawerDisabled}
				/>
			{/key}
		</div>
	</Drawer>

	<div
		class="mt-1.5 py-2 bg-white dark:bg-gray-900 rounded-3xl border border-gray-100/30 dark:border-gray-850/30"
	>
		<div class="flex w-full items-center gap-2 py-0.5 px-3.5 pb-2">
			<div class="flex flex-1 min-w-0">
				<div class=" self-center ml-1 mr-3">
					<Search className="size-3.5" />
				</div>
				<input
					class=" w-full text-sm pr-4 py-1 rounded-r-xl outline-hidden bg-transparent"
					bind:value={query}
					aria-label={$i18n.t('Search Prompt Apps')}
					placeholder={$i18n.t('Search Prompt Apps')}
				/>

				{#if query}
					<div class="self-center pl-1.5 translate-y-[0.5px] rounded-l-xl bg-transparent">
						<button
							class="p-0.5 rounded-full hover:bg-gray-100 dark:hover:bg-gray-900 transition"
							aria-label={$i18n.t('Clear search')}
							on:click={() => {
								query = '';
							}}
						>
							<XMark className="size-3" strokeWidth="2" />
						</button>
					</div>
				{/if}
			</div>

			<button
				class="shrink-0 px-3 py-1.5 rounded-xl bg-black text-white dark:bg-white dark:text-black transition font-medium text-sm flex items-center"
				type="button"
				on:click={() => {
					createPromptSeed = null;
					clonePrompt = false;
					editPrompt = false;
					drawerDisabled = false;
					showCreateDrawer = true;
				}}
			>
				<Plus className="size-3" strokeWidth="2.5" />

				<div class="ml-1 text-xs">{$i18n.t('New Prompt App')}</div>
			</button>
		</div>

		<div
			class="px-3 flex w-full bg-transparent overflow-x-auto scrollbar-none -mx-1"
			on:wheel={(e) => {
				if (e.deltaY !== 0) {
					e.preventDefault();
					e.currentTarget.scrollLeft += e.deltaY;
				}
			}}
		>
			<div
				class="flex gap-0.5 w-fit text-center text-sm rounded-full bg-transparent px-1.5 whitespace-nowrap"
				bind:this={tagsContainerElement}
			>
				<ViewSelector
					bind:value={viewOption}
					includeShared={false}
					onChange={async (value) => {
						localStorage.workspaceViewOption = value;
						page = 1;
						await tick();
					}}
				/>

				{#if (tags ?? []).length > 0}
					<TagSelector
						bind:value={selectedTag}
						items={tags.map((tag) => ({ value: tag, label: tag }))}
					/>
				{/if}
			</div>
		</div>

		{#if prompts === null || loading}
			<div class="w-full h-full flex justify-center items-center my-16 mb-24">
				<Spinner className="size-5" />
			</div>
		{:else if (prompts ?? []).length !== 0}
			<!-- Before they call, I will answer; while they are yet speaking, I will hear. -->
			<div class="gap-2 grid my-2 px-3 lg:grid-cols-2">
				{#each prompts as prompt (prompt.id)}
					<div
						role="button"
						tabindex="0"
						class=" flex space-x-4 cursor-pointer text-left w-full px-3 py-2.5 dark:hover:bg-gray-850/50 hover:bg-gray-50 transition rounded-2xl"
						on:click={() => openEditDrawer(prompt)}
						on:keydown={(e) => {
							if (e.key === 'Enter' || e.key === ' ') {
								e.preventDefault();
								openEditDrawer(prompt);
							}
						}}
					>
						<div class=" flex flex-col flex-1 space-x-4 cursor-pointer w-full pl-1">
							<div class="flex items-center justify-between w-full mb-0.5">
								<div class="flex items-center gap-2">
									<div class="font-medium line-clamp-1 capitalize">{prompt.name}</div>
								</div>
								{#if !prompt.write_access}
									<Badge type="muted" content={$i18n.t('Read Only')} />
								{/if}
							</div>

							<div class="flex gap-1 text-xs text-gray-500">
								<Tooltip
									content={prompt?.user?.email ?? $i18n.t('Deleted User')}
									className="flex shrink-0"
									placement="top-start"
								>
									<div class="shrink-0 text-gray-500">
										{$i18n.t('By {{name}}', {
											name: capitalizeFirstLetter(
												prompt?.user?.name ?? prompt?.user?.email ?? $i18n.t('Deleted User')
											)
										})}
									</div>
								</Tooltip>

								<div>·</div>

								{#if prompt.description?.trim()}
									<Tooltip content={prompt.description} placement="top">
										<div class="line-clamp-1 min-w-0">
											{prompt.description}
										</div>
									</Tooltip>
								{:else}
									<div class="line-clamp-1 text-gray-400 dark:text-gray-600">
										{$i18n.t('No description')}
									</div>
								{/if}
							</div>
						</div>
						<div class="flex flex-row gap-0.5 self-center">
							{#if shiftKey}
								<Tooltip content={$i18n.t('Delete')}>
									<button
										class="self-center w-fit text-sm px-2 py-2 dark:text-gray-300 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/5 rounded-xl"
										type="button"
										aria-label={$i18n.t('Delete')}
										on:click|stopPropagation={() => {
											deleteHandler(prompt);
										}}
									>
										<GarbageBin />
									</button>
								</Tooltip>
							{:else}
								<span on:click|stopPropagation>
									<PromptMenu
										cloneHandler={() => {
											cloneHandler(prompt);
										}}
										deleteHandler={async () => {
											deletePrompt = prompt;
											showDeleteConfirm = true;
										}}
										onClose={() => {}}
									>
										<button
											class="self-center w-fit text-sm p-1.5 dark:text-gray-300 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/5 rounded-xl"
											type="button"
										>
											<EllipsisHorizontal className="size-5" />
										</button>
									</PromptMenu>
								</span>

								<button on:click|stopPropagation|preventDefault>
									<Tooltip
										content={prompt.is_active !== false ? $i18n.t('Enabled') : $i18n.t('Disabled')}
									>
										<Switch
											bind:state={prompt.is_active}
											on:change={async () => {
												togglePromptById(localStorage.token, prompt.id);
											}}
										/>
									</Tooltip>
								</button>
							{/if}
						</div>
					</div>
				{/each}
			</div>

			{#if total > 30}
				<div class="flex justify-center mt-4 mb-2">
					<Pagination bind:page count={total} perPage={30} />
				</div>
			{/if}
		{:else}
			<div class=" w-full h-full flex flex-col justify-center items-center my-16 mb-24">
				<div class="max-w-md text-center">
					<div class=" text-3xl mb-3">😕</div>
					<div class=" text-lg font-medium mb-1">{$i18n.t('No prompt apps found')}</div>
					<div class=" text-gray-500 text-center text-xs">
						{$i18n.t('Try adjusting your search or filter to find what you are looking for.')}
					</div>
				</div>
			</div>
		{/if}
	</div>
{:else}
	<div class="w-full h-full flex justify-center items-center">
		<Spinner className="size-5" />
	</div>
{/if}

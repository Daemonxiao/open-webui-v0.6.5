<script lang="ts">
	import { toast } from 'svelte-sonner';
	import { getContext } from 'svelte';

	import dayjs from 'dayjs';
	import localizedFormat from 'dayjs/plugin/localizedFormat';
	import calendar from 'dayjs/plugin/calendar';

	dayjs.extend(localizedFormat);
	dayjs.extend(calendar);

	import { deleteChatById, getChatById } from '$lib/apis/chats';
	import { WEBUI_API_BASE_URL } from '$lib/constants';
	import { user as currentUser } from '$lib/stores';

	import Modal from '$lib/components/common/Modal.svelte';
	import Drawer from '$lib/components/common/Drawer.svelte';
	import Tooltip from '$lib/components/common/Tooltip.svelte';
	import ConfirmDialog from '$lib/components/common/ConfirmDialog.svelte';

	import Spinner from '../common/Spinner.svelte';
	import Loader from '../common/Loader.svelte';
	import XMark from '../icons/XMark.svelte';
	import ChevronUp from '../icons/ChevronUp.svelte';
	import ChevronDown from '../icons/ChevronDown.svelte';
	import Link from '../icons/Link.svelte';
	import LinkSlash from '../icons/LinkSlash.svelte';
	import Clipboard from '../icons/Clipboard.svelte';
	import Messages from '../chat/Messages.svelte';

	const i18n = getContext('i18n');

	export let show = false;

	export let title = 'Chats';
	export let variant: 'modal' | 'drawer' = 'modal';
	export let emptyPlaceholder = '';
	export let shareUrl = false;
	export let showUserInfo = false;
	export let showSearch = true;
	export let readOnly = false;

	export let query = '';

	export let orderBy = 'updated_at';
	export let direction = 'desc'; // 'asc' or 'desc'

	export let chatList = null;
	export let allChatsLoaded = false;
	export let chatListLoading = false;

	let deleteChatId = null;
	let selectedIdx = 0;
	let showDeleteConfirmDialog = false;
	let previewChatId = null;
	let previewChat = null;
	let previewHistory = null;
	let previewSelectedModels = [''];
	let previewChatLoading = false;
	let previewChatError = '';
	let previewRequestId = 0;
	let lastQuery = query;

	export let onUpdate = () => {};
	export let onDelete: (id: string) => void = () => {};

	export let loadHandler: null | Function = null;
	export let unarchiveHandler: null | Function = null;
	export let unshareHandler: null | Function = null;

	const setSortKey = (key) => {
		if (orderBy === key) {
			direction = direction === 'asc' ? 'desc' : 'asc';
		} else {
			orderBy = key;
			direction = 'asc';
		}
	};

	const deleteHandler = async (chatId) => {
		const res = await deleteChatById(localStorage.token, chatId).catch((error) => {
			toast.error(`${error}`);
		});

		if (res) {
			onDelete(chatId);
		}
		onUpdate();
	};

	const resetPreview = () => {
		previewChatId = null;
		previewChat = null;
		previewHistory = null;
		previewSelectedModels = [''];
		previewChatLoading = false;
		previewChatError = '';
		previewRequestId += 1;
	};

	const selectChatForPreview = async (chat) => {
		if (variant !== 'drawer' || !chat?.id) {
			return;
		}

		const requestId = ++previewRequestId;
		previewChatId = chat.id;
		previewChat = chat;
		previewHistory = null;
		previewSelectedModels = [''];
		previewChatError = '';
		previewChatLoading = true;

		const res = await getChatById(localStorage.token, chat.id).catch((error) => {
			toast.error(`${error}`);
			return null;
		});

		if (requestId !== previewRequestId) {
			return;
		}

		previewChatLoading = false;

		if (!res) {
			previewChatError = $i18n.t('Failed to load chat preview');
			return;
		}

		const models = res?.chat?.models;
		previewChat = res;
		previewSelectedModels = Array.isArray(models) ? models : [models ?? ''];
		previewHistory = res?.chat?.history ?? { messages: {}, currentId: null };
	};

	$: if (variant === 'drawer' && show && query !== lastQuery) {
		lastQuery = query;
		resetPreview();
	}

	$: if (variant === 'drawer' && show && chatList?.length && !previewChatId && !previewChatLoading) {
		selectChatForPreview(chatList[0]);
	}

	$: if (!show && previewChatId) {
		resetPreview();
	}
</script>

<ConfirmDialog
	bind:show={showDeleteConfirmDialog}
	on:confirm={() => {
		if (deleteChatId) {
			deleteHandler(deleteChatId);
			deleteChatId = null;
		}
	}}
/>

<svelte:component
	this={variant === 'drawer' ? Drawer : Modal}
	bind:show
	{...(variant === 'drawer'
		? {
				side: 'right',
				className:
					'w-full lg:w-[76rem] xl:w-[84rem] !bg-white dark:!bg-gray-900 shadow-3xl border-l border-gray-100 dark:border-gray-850'
			}
		: { size: 'lg' })}
>
	<div class={variant === 'drawer' ? 'h-full min-h-0 flex flex-col' : ''}>
		<div class=" flex justify-between dark:text-gray-300 px-5 pt-4 pb-1">
			<div class=" text-lg font-medium self-center">{title}</div>
			<button
				class="self-center"
				on:click={() => {
					show = false;
				}}
			>
				<svg
					xmlns="http://www.w3.org/2000/svg"
					viewBox="0 0 20 20"
					fill="currentColor"
					class="w-5 h-5"
				>
					<path
						fill-rule="evenodd"
						d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z"
						clip-rule="evenodd"
					/>
				</svg>
			</button>
		</div>

		<div
			class="flex flex-col w-full px-5 pb-4 dark:text-gray-200 {variant === 'drawer'
				? 'flex-1 min-h-0'
				: ''}"
		>
			{#if showSearch}
				<div class=" flex w-full space-x-2 mt-0.5 mb-1.5">
					<div class="flex flex-1">
						<div class=" self-center ml-1 mr-3">
							<svg
								xmlns="http://www.w3.org/2000/svg"
								viewBox="0 0 20 20"
								fill="currentColor"
								class="w-4 h-4"
							>
								<path
									fill-rule="evenodd"
									d="M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z"
									clip-rule="evenodd"
								/>
							</svg>
						</div>
						<input
							class=" w-full text-sm pr-4 py-1 rounded-r-xl outline-hidden bg-transparent"
							bind:value={query}
							placeholder={$i18n.t('Search Chats')}
							maxlength="500"
						/>

						{#if query}
							<div class="self-center pl-1.5 pr-1 translate-y-[0.5px] rounded-l-xl bg-transparent">
								<button
									class="p-0.5 rounded-full hover:bg-gray-100 dark:hover:bg-gray-900 transition"
									on:click={() => {
										query = '';
										selectedIdx = 0;
									}}
								>
									<XMark className="size-3" strokeWidth="2" />
								</button>
							</div>
						{/if}
					</div>
				</div>
			{/if}

			<div
				class=" flex flex-col w-full {variant === 'drawer'
					? 'flex-1 min-h-0 lg:flex-row lg:space-x-0 lg:gap-4'
					: 'sm:flex-row sm:justify-center sm:space-x-6'}"
			>
				{#if chatList}
					<div
						class="w-full {variant === 'drawer'
							? 'h-1/2 min-h-0 flex flex-col lg:h-full lg:w-[26rem] lg:shrink-0 lg:pr-4'
							: ''}"
					>
						{#if chatList.length > 0}
							<div class="flex text-xs font-medium mb-1.5">
								{#if showUserInfo}
									<div class="px-1.5 py-1 w-32">
										{$i18n.t('User')}
									</div>
								{/if}
								<button
									class="px-1.5 py-1 cursor-pointer select-none {showUserInfo
										? 'flex-1'
										: 'basis-3/5'}"
									on:click={() => setSortKey('title')}
								>
									<div class="flex gap-1.5 items-center">
										{$i18n.t('Title')}

										{#if orderBy === 'title'}
											<span class="font-normal"
												>{#if direction === 'asc'}
													<ChevronUp className="size-2" />
												{:else}
													<ChevronDown className="size-2" />
												{/if}
											</span>
										{:else}
											<span class="invisible">
												<ChevronUp className="size-2" />
											</span>
										{/if}
									</div>
								</button>
								<button
									class="px-1.5 py-1 cursor-pointer select-none hidden sm:flex {showUserInfo
										? 'w-28'
										: 'sm:basis-2/5'} justify-end"
									on:click={() => setSortKey('updated_at')}
								>
									<div class="flex gap-1.5 items-center">
										{$i18n.t('Updated at')}

										{#if orderBy === 'updated_at'}
											<span class="font-normal"
												>{#if direction === 'asc'}
													<ChevronUp className="size-2" />
												{:else}
													<ChevronDown className="size-2" />
												{/if}
											</span>
										{:else}
											<span class="invisible">
												<ChevronUp className="size-2" />
											</span>
										{/if}
									</div>
								</button>
							</div>
						{/if}
						<div
							class="text-left text-sm w-full mb-3 {variant === 'drawer'
								? 'flex-1 min-h-0 overflow-y-auto'
								: 'max-h-[22rem] overflow-y-scroll'}"
						>
							{#if chatList.length === 0}
								<div
									class="text-xs text-gray-500 dark:text-gray-400 text-center px-5 min-h-20 w-full h-full flex justify-center items-center"
								>
									{$i18n.t('No results found')}
								</div>
							{/if}

							{#each chatList as chat, idx (chat.id)}
								{#if (idx === 0 || (idx > 0 && chat.time_range !== chatList[idx - 1].time_range)) && chat?.time_range}
									<div
										class="w-full text-xs text-gray-500 dark:text-gray-500 font-medium {idx === 0
											? ''
											: 'pt-5'} pb-2 px-2"
									>
										{$i18n.t(chat.time_range)}
										<!-- localisation keys for time_range to be recognized from the i18next parser (so they don't get automatically removed):
							{$i18n.t('Today')}
							{$i18n.t('Yesterday')}
							{$i18n.t('Previous 7 days')}
							{$i18n.t('Previous 30 days')}
							{$i18n.t('January')}
							{$i18n.t('February')}
							{$i18n.t('March')}
							{$i18n.t('April')}
							{$i18n.t('May')}
							{$i18n.t('June')}
							{$i18n.t('July')}
							{$i18n.t('August')}
							{$i18n.t('September')}
							{$i18n.t('October')}
							{$i18n.t('November')}
							{$i18n.t('December')}
							-->
									</div>
								{/if}

								<div
									class=" w-full flex items-center rounded-lg text-sm py-2 px-3 hover:bg-gray-50 dark:hover:bg-gray-850 {variant ===
										'drawer' && previewChatId === chat.id
										? 'bg-gray-50 dark:bg-gray-850'
										: ''}"
									draggable="false"
								>
									{#if showUserInfo && chat.user_id}
										<div class="w-32 shrink-0 flex items-center gap-2">
											<img
												src="{WEBUI_API_BASE_URL}/users/{chat.user_id}/profile/image"
												alt={chat.user_name || 'User'}
												class="size-5 rounded-full object-cover shrink-0"
											/>
											<span class="text-xs text-gray-600 dark:text-gray-400 truncate"
												>{chat.user_name || 'Unknown'}</span
											>
										</div>
									{/if}
									{#if variant === 'drawer'}
										<button
											type="button"
											class="{showUserInfo ? 'flex-1' : 'basis-3/5'} text-left min-w-0"
											on:click={() => selectChatForPreview(chat)}
										>
											<div class="text-ellipsis line-clamp-1 w-full">
												{chat?.title}
											</div>
										</button>
									{:else}
										<a
											class={showUserInfo ? 'flex-1' : 'basis-3/5'}
											href={shareUrl ? `/s/${chat.id}` : `/c/${chat.id}`}
											on:click={() => (show = false)}
										>
											<div class="text-ellipsis line-clamp-1 w-full">
												{chat?.title}
											</div>
										</a>
									{/if}

									<div class="{showUserInfo ? 'w-28' : 'basis-2/5'} flex items-center justify-end">
										<div class="hidden sm:flex text-gray-500 dark:text-gray-400 text-xs">
											{$i18n.t(
												dayjs(chat?.updated_at * 1000).calendar(null, {
													sameDay: '[Today]',
													nextDay: '[Tomorrow]',
													nextWeek: 'dddd',
													lastDay: '[Yesterday]',
													lastWeek: '[Last] dddd',
													sameElse: 'L' // use localized format, otherwise dayjs.calendar() defaults to DD/MM/YYYY
												})
											)}
										</div>

										{#if !readOnly}
											<div class="flex justify-end pl-2.5 text-gray-600 dark:text-gray-300">
												{#if unarchiveHandler}
													<Tooltip content={$i18n.t('Unarchive Chat')}>
														<button
															class="self-center w-fit px-1 text-sm rounded-xl"
															on:click={async (e) => {
																e.stopImmediatePropagation();
																e.stopPropagation();
																unarchiveHandler(chat.id);
															}}
														>
															<svg
																xmlns="http://www.w3.org/2000/svg"
																fill="none"
																viewBox="0 0 24 24"
																stroke-width="1.5"
																stroke="currentColor"
																class="size-4"
															>
																<path
																	stroke-linecap="round"
																	stroke-linejoin="round"
																	d="M9 8.25H7.5a2.25 2.25 0 0 0-2.25 2.25v9a2.25 2.25 0 0 0 2.25 2.25h9a2.25 2.25 0 0 0 2.25-2.25v-9a2.25 2.25 0 0 0-2.25-2.25H15m0-3-3-3m0 0-3 3m3-3V15"
																/>
															</svg>
														</button>
													</Tooltip>
												{/if}

												{#if unshareHandler && chat.share_id}
													<Tooltip content={$i18n.t('Copy Share Link')}>
														<button
															class="self-center w-fit px-1 text-sm rounded-xl"
															on:click={async (e) => {
																e.stopImmediatePropagation();
																e.stopPropagation();
																const shareUrl = `${window.location.origin}/s/${chat.share_id}`;
																await navigator.clipboard.writeText(shareUrl);
																toast.success($i18n.t('Share link copied to clipboard.'));
															}}
														>
															<Clipboard class="size-4" strokeWidth="1.5" />
														</button>
													</Tooltip>
												{/if}

												<Tooltip
													content={unshareHandler
														? $i18n.t('Unshare Chat')
														: $i18n.t('Delete Chat')}
												>
													<button
														class="self-center w-fit px-1 text-sm rounded-xl"
														on:click={async (e) => {
															e.stopImmediatePropagation();
															e.stopPropagation();
															if (unshareHandler) {
																unshareHandler(chat.id);
															} else {
																deleteChatId = chat.id;
																showDeleteConfirmDialog = true;
															}
														}}
													>
														{#if unshareHandler}
															<LinkSlash />
														{:else}
															<svg
																xmlns="http://www.w3.org/2000/svg"
																fill="none"
																viewBox="0 0 24 24"
																stroke-width="1.5"
																stroke="currentColor"
																class="w-4 h-4"
															>
																<path
																	stroke-linecap="round"
																	stroke-linejoin="round"
																	d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
																/>
															</svg>
														{/if}
													</button>
												</Tooltip>
											</div>
										{/if}
									</div>
								</div>
							{/each}

							{#if !allChatsLoaded && loadHandler}
								<Loader
									on:visible={(e) => {
										if (!chatListLoading) {
											loadHandler();
										}
									}}
								>
									<div
										class="w-full flex justify-center py-1 text-xs animate-pulse items-center gap-2"
									>
										<Spinner className=" size-4" />
										<div class=" ">{$i18n.t('Loading...')}</div>
									</div>
								</Loader>
							{/if}
						</div>

						{#if query === ''}
							<slot name="footer"></slot>
						{/if}
					</div>

					{#if variant === 'drawer'}
						<div
							class="mt-4 flex h-1/2 min-h-0 flex-1 flex-col border-t border-gray-100 pt-4 dark:border-gray-850 lg:mt-0 lg:h-full lg:border-l lg:border-t-0 lg:pl-4 lg:pt-0"
						>
							<div class="mb-3 flex min-h-10 items-start justify-between gap-3">
								<div class="min-w-0">
									<div class="text-sm font-medium line-clamp-1">
										{previewChat?.title ?? $i18n.t('Select a conversation to preview')}
									</div>
									{#if previewChat?.updated_at}
										<div class="mt-1 text-xs text-gray-500 dark:text-gray-400">
											{$i18n.t('Updated at')}: {dayjs(previewChat.updated_at * 1000).format('LLL')}
										</div>
									{/if}
								</div>
								{#if previewChatId}
									<a
										class="shrink-0 rounded-lg px-2 py-1 text-xs text-gray-500 transition hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-850 dark:hover:text-gray-200"
										href={shareUrl ? `/s/${previewChatId}` : `/c/${previewChatId}`}
										target="_blank"
										rel="noreferrer"
									>
										{$i18n.t('Open')}
									</a>
								{/if}
							</div>

							<div
								id="messages-container"
								class="flex-1 min-h-0 overflow-y-auto rounded-lg border border-gray-100 bg-gray-50/40 px-3 dark:border-gray-850 dark:bg-gray-950/20 @container"
							>
								{#if previewChatLoading}
									<div class="flex h-full items-center justify-center">
										<Spinner className="size-5" />
									</div>
								{:else if previewChatError}
									<div
										class="flex h-full items-center justify-center px-4 text-center text-sm text-gray-500 dark:text-gray-400"
									>
										{previewChatError}
									</div>
								{:else if previewHistory}
									<Messages
										className="h-full flex pt-2 pb-8 w-full"
										chatId={`admin-chat-preview-${previewChatId ?? ''}`}
										user={$currentUser}
										prompt=""
										readOnly={true}
										editCodeBlock={false}
										selectedModels={previewSelectedModels}
										atSelectedModel=""
										bind:history={previewHistory}
										autoScroll={false}
										messagesCount={null}
										sendMessage={() => {}}
										continueResponse={() => {}}
										regenerateResponse={() => {}}
										mergeResponses={() => {}}
										chatActionHandler={() => {}}
									/>
								{:else}
									<div
										class="flex h-full items-center justify-center px-4 text-center text-sm text-gray-500 dark:text-gray-400"
									>
										{$i18n.t('Select a conversation to preview')}
									</div>
								{/if}
							</div>
						</div>
					{/if}
				{:else}
					<div class="w-full h-full flex justify-center items-center min-h-20">
						<Spinner className="size-5" />
					</div>
				{/if}

				<!-- {#if chats !== null}
					{#if chats.length > 0}
						<div class="w-full">
							<div class="text-left text-sm w-full mb-3 max-h-[22rem] overflow-y-scroll">
								<div class="relative overflow-x-auto">
									<table
										class="w-full text-sm text-left text-gray-600 dark:text-gray-400 table-auto"
									>
										<thead
											class="text-xs text-gray-700 uppercase bg-transparent dark:text-gray-200 border-b-1 border-gray-50 dark:border-gray-850/30"
										>
											<tr>
												<th scope="col" class="px-3 py-2"> {$i18n.t('Name')} </th>
												<th scope="col" class="px-3 py-2 hidden md:flex">
													{$i18n.t('Created At')}
												</th>
												<th scope="col" class="px-3 py-2 text-right" />
											</tr>
										</thead>
										<tbody>
											{#each chats as chat, idx}
												<tr
													class="bg-transparent {idx !== chats.length - 1 &&
														'border-b'} border-gray-50 dark:border-gray-850/30 text-xs"
												>
													<td class="px-3 py-1 w-2/3">
														<a href="/c/{chat.id}" target="_blank">
															<div class=" hover:underline line-clamp-1">
																{chat.title}
															</div>
														</a>
													</td>

													<td class=" px-3 py-1 hidden md:flex h-[2.5rem]">
														<div class="my-auto">
															{dayjs(chat.created_at * 1000).format('LLL')}
														</div>
													</td>

													<td class="px-3 py-1 text-right">
														<div class="flex justify-end w-full">
															{#if unarchiveHandler}
																<Tooltip content={$i18n.t('Unarchive Chat')}>
																	<button
																		class="self-center w-fit text-sm px-2 py-2 hover:bg-black/5 dark:hover:bg-white/5 rounded-xl"
																		on:click={async () => {
																			unarchiveHandler(chat.id);
																		}}
																	>
																		<svg
																			xmlns="http://www.w3.org/2000/svg"
																			fill="none"
																			viewBox="0 0 24 24"
																			stroke-width="1.5"
																			stroke="currentColor"
																			class="size-4"
																		>
																			<path
																				stroke-linecap="round"
																				stroke-linejoin="round"
																				d="M9 8.25H7.5a2.25 2.25 0 0 0-2.25 2.25v9a2.25 2.25 0 0 0 2.25 2.25h9a2.25 2.25 0 0 0 2.25-2.25v-9a2.25 2.25 0 0 0-2.25-2.25H15m0-3-3-3m0 0-3 3m3-3V15"
																			/>
																		</svg>
																	</button>
																</Tooltip>
															{/if}

															<Tooltip content={$i18n.t('Delete Chat')}>
																<button
																	class="self-center w-fit text-sm px-2 py-2 hover:bg-black/5 dark:hover:bg-white/5 rounded-xl"
																	on:click={async () => {
																		deleteHandler(chat.id);
																	}}
																>
																	<svg
																		xmlns="http://www.w3.org/2000/svg"
																		fill="none"
																		viewBox="0 0 24 24"
																		stroke-width="1.5"
																		stroke="currentColor"
																		class="w-4 h-4"
																	>
																		<path
																			stroke-linecap="round"
																			stroke-linejoin="round"
																			d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
																		/>
																	</svg>
																</button>
															</Tooltip>
														</div>
													</td>
												</tr>
											{/each}
										</tbody>
									</table>
								</div>
							</div>

							<slot name="footer"></slot>
						</div>
					{:else}
						<div class="text-left text-sm w-full mb-8">
							{emptyPlaceholder || $i18n.t('No chats found.')}
						</div>
					{/if}
				{:else}
					<div class="w-full h-full">
						<Spinner />
					</div>
				{/if} -->
			</div>
		</div>
	</div>
</svelte:component>
